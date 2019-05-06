defmodule Core.Divisions do
  @moduledoc """
  The boundary for the Divisions system.
  """

  use Core.Search, Application.get_env(:core, :repos)[:read_prm_repo]

  import Core.API.Helpers.Connection, only: [get_client_id: 1, get_consumer_id: 1]
  import Ecto.Changeset, warn: false

  alias Core.Divisions.Division
  alias Core.Divisions.Search
  alias Core.Email.Sanitizer
  alias Core.LegalEntities
  alias Core.LegalEntities.LegalEntity
  alias Core.PRMRepo
  alias Core.ValidationError
  alias Core.Validators.Addresses
  alias Core.Validators.Error
  alias Core.Validators.JsonObjects
  alias Core.Validators.JsonSchema
  alias Ecto.Multi
  alias EctoTrail.Changelog
  alias Scrivener.Page

  @uaddresses_api Application.get_env(:core, :api_resolvers)[:uaddresses]
  @read_prm_repo Application.get_env(:core, :repos)[:read_prm_repo]

  @search_fields ~w(
    ids
    name
    legal_entity_id
    type
    status
  )a

  @fields_optional ~w(
    external_id
    mountain_group
    is_active
    location
    working_hours
    dls_id
    dls_verified
  )a

  @fields_required ~w(
    legal_entity_id
    name
    type
    phones
    status
    email
  )a

  @mountain_group_required_types %{mountain_group: :boolean, settlement_id: Ecto.UUID}
  @status_active Division.status(:active)
  @default_mountain_group "0"

  def list(params) do
    with %Page{entries: entries} = page <-
           %Search{}
           |> changeset(params)
           |> search(params, Division) do
      %{page | entries: @read_prm_repo.preload(entries, :addresses)}
    end
  end

  def get_by_id!(id) do
    Division
    |> @read_prm_repo.get!(id)
    |> @read_prm_repo.preload(:addresses)
  end

  def get_by_id(id) do
    Division
    |> @read_prm_repo.get(id)
    |> @read_prm_repo.preload(:addresses)
  end

  def get_by_ids(ids) when is_list(ids) do
    Division
    |> where([d], d.id in ^ids)
    |> @read_prm_repo.all()
    |> @read_prm_repo.preload(:addresses)
  end

  def search(legal_entity_id, params \\ %{}) do
    params
    |> Map.put("legal_entity_id", legal_entity_id)
    |> list()
  end

  def create(params, headers) do
    with {:ok, attrs} <- prepare_division_data(params, get_client_id(headers)),
         attrs <- Map.merge(attrs, %{"status" => @status_active, "is_active" => true}) do
      %Division{}
      |> changeset(attrs)
      |> PRMRepo.insert_and_log(get_consumer_id(headers))
    end
  end

  def update(id, params, headers) do
    legal_entity_id = get_client_id(headers)

    with {:ok, attrs} <- prepare_division_data(params, legal_entity_id),
         %Division{} = division <- get_by_id(id),
         :ok <- validate_legal_entity(division, legal_entity_id) do
      division
      |> changeset(attrs)
      |> PRMRepo.update_and_log(get_consumer_id(headers))
    end
  end

  defp prepare_division_data(params, legal_entity_id) do
    with %LegalEntity{} = legal_entity <- LegalEntities.get_by_id(legal_entity_id),
         :ok <- validate_division_type(legal_entity, params),
         params <-
           params
           |> Map.delete("id")
           |> Map.put("legal_entity_id", legal_entity_id),
         :ok <- JsonSchema.validate(:division, params),
         params <- lowercase_email(params),
         :ok <- validate_json_objects(params),
         :ok <- validate_addresses(params) do
      put_mountain_group(params)
    else
      nil ->
        Error.dump(%ValidationError{
          description: "invalid legal entity",
          path: "$.legal_entity_id"
        })

      err ->
        err
    end
  end

  def update_status(id, status, headers) do
    with %Division{} = division <- get_by_id(id),
         :ok <- validate_legal_entity(division, get_client_id(headers)),
         attrs <- %{"status" => status, "is_active" => status == @status_active} do
      division
      |> changeset(attrs)
      |> PRMRepo.update_and_log(get_consumer_id(headers))
    end
  end

  def update_mountain_group(attrs, consumer_id) do
    case mountain_group_changeset(attrs) do
      %Ecto.Changeset{valid?: true} -> do_update_divisions_mountain_group(attrs, consumer_id)
      err_changeset -> err_changeset
    end
  end

  def validate_json_objects(data) do
    with :ok <- JsonObjects.array_unique_by_key(data, ["addresses"], "type"),
         :ok <- JsonObjects.array_unique_by_key(data, ["phones"], "type"),
         do: :ok
  end

  def validate_addresses(data) do
    addresses = Map.get(data, "addresses") || []
    Addresses.validate(addresses, "RESIDENCE")
  end

  defp validate_division_type(%LegalEntity{type: legal_entity_type}, params) do
    config = Confex.fetch_env!(:core, :legal_entity_division_types)

    legal_entity_type =
      legal_entity_type
      |> String.downcase()
      |> String.to_atom()

    allowed_types = Keyword.get(config, legal_entity_type)
    type = Map.get(params, "type")

    if !type || Enum.member?(allowed_types, type) do
      :ok
    else
      Error.dump(%ValidationError{
        description: "value is not allowed in enum",
        path: "$.type",
        params: allowed_types,
        rule: "inclusion"
      })
    end
  end

  def put_mountain_group(%{"addresses" => addresses} = division) do
    settlement_id =
      addresses
      |> List.first()
      |> Map.fetch!("settlement_id")

    settlement_id
    |> @uaddresses_api.get_settlement_by_id([])
    |> put_mountain_group(division)
  end

  def put_mountain_group(err), do: err

  def put_mountain_group({:ok, %{"data" => address}}, division) do
    mountain_group = Map.get(address, "mountain_group", @default_mountain_group)
    {:ok, Map.put(division, "mountain_group", mountain_group)}
  end

  def put_mountain_group(err, _division), do: err

  def validate_legal_entity(%Division{} = division, legal_entity_id) do
    case legal_entity_id == division.legal_entity_id do
      true -> :ok
      false -> {:error, :forbidden}
    end
  end

  def changeset(
        %Division{} = division,
        %{"location" => %{"longitude" => lng, "latitude" => lat}} = attrs
      ) do
    division
    |> changeset(Map.put(attrs, "location", %Geo.Point{coordinates: {lng, lat}}))
    |> cast_assoc(:addresses)
  end

  def changeset(%Division{} = division, attrs) do
    division
    |> cast(attrs, @fields_optional ++ @fields_required)
    |> validate_required(@fields_required)
    |> foreign_key_constraint(:legal_entity_id)
    |> cast_assoc(:addresses)
  end

  def changeset(%Search{} = division, attrs) do
    cast(division, attrs, @search_fields)
  end

  defp mountain_group_changeset(attrs) do
    required_params = Map.keys(@mountain_group_required_types)

    {%{}, @mountain_group_required_types}
    |> cast(attrs, required_params)
    |> validate_required(required_params)
  end

  def get_search_query(Division = entity, %{ids: _} = changes) do
    super(entity, convert_comma_params_to_where_in_clause(changes, :ids, :id))
  end

  def get_search_query(Division = division, changes) do
    params =
      changes
      |> Map.drop([:name])
      |> Map.to_list()

    division
    |> select([d], d)
    |> query_name(Map.get(changes, :name))
    |> where(^params)
  end

  defp query_name(query, nil), do: query

  defp query_name(query, name) do
    query |> where([d], ilike(d.name, ^"%#{name}%"))
  end

  defp convert_comma_params_to_where_in_clause(changes, param_name, db_field) do
    changes
    |> Map.put(db_field, {String.split(changes[param_name], ","), :in})
    |> Map.delete(param_name)
  end

  defp do_update_divisions_mountain_group(attrs, consumer_id) do
    %{settlement_id: settlement_id, mountain_group: mountain_group} = attrs

    query =
      Division
      |> select([d], [:id, :mountain_group])
      |> where([d], d.mountain_group != ^mountain_group)
      |> join(:inner, [d], c in assoc(d, :addresses))
      |> where([d, c], c.settlement_id == ^settlement_id)

    Multi.new()
    |> Multi.update_all(
      :update_divisions_mountain_group,
      query,
      set: [mountain_group: mountain_group, updated_at: DateTime.utc_now()]
    )
    |> Multi.run(:log_updates, &log_changes(&1, &2, consumer_id))
    |> PRMRepo.transaction()
  end

  defp log_changes(_, %{update_divisions_mountain_group: {_, updated_divisions}}, consumer_id) do
    changes =
      updated_divisions
      |> Enum.map(fn division ->
        %{
          actor_id: consumer_id,
          resource: "divisions",
          resource_id: division.id,
          changeset: %{mountain_group: division.mountain_group}
        }
      end)
      |> Enum.map(&Map.put(&1, :inserted_at, DateTime.utc_now()))

    {_, changelog} = PRMRepo.insert_all(Changelog, changes, returning: true)
    {:ok, changelog}
  end

  defp lowercase_email(params) do
    email = Map.get(params, "email")
    Map.put(params, email, Sanitizer.sanitize(email))
  end
end
