defmodule Core.DeclarationRequests.API.V2.Creator do
  @moduledoc false
  import Ecto.Changeset

  alias Core.DeclarationRequests.API.V1.Creator, as: V1Creator
  alias Core.DeclarationRequests.API.V2.MpiSearch
  alias Core.DeclarationRequests.API.V2.Persons
  alias Core.DeclarationRequests.DeclarationRequest
  alias Core.GlobalParameters
  alias Core.Repo
  alias Ecto.Changeset

  @auth_na DeclarationRequest.authentication_method(:na)
  @channel_cabinet DeclarationRequest.channel(:cabinet)

  def create(params, user_id, person, employee, division, legal_entity) do
    global_parameters = GlobalParameters.get_values()

    auxiliary_entities = %{
      employee: employee,
      global_parameters: global_parameters,
      division: division,
      legal_entity: legal_entity,
      person_id: person["id"]
    }

    pending_declaration_requests = pending_declaration_requests(person, employee.id, legal_entity.id)

    Repo.transaction(fn ->
      cancel_declaration_requests(user_id, pending_declaration_requests)

      with {:ok, declaration_request} <- insert_declaration_request(params, user_id, auxiliary_entities),
           {:ok, declaration_request} <- finalize(declaration_request),
           {:ok, urgent_data} <- prepare_urgent_data(declaration_request) do
        %{urgent_data: urgent_data, finalize: declaration_request}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defdelegate pending_declaration_requests(person, employee_id, legal_entity_id), to: V1Creator

  defdelegate cancel_declaration_requests(user_id, pending_declaration_requests), to: V1Creator

  defdelegate finalize(declaration_request), to: V1Creator
  defdelegate prepare_urgent_data(declaration_request), to: V1Creator

  defdelegate changeset(attrs, user_id, auxiliary_entities), to: V1Creator

  defdelegate generate_printout_form(changeset, employee), to: V1Creator
  defdelegate do_insert_declaration_request(changeset), to: V1Creator
  defdelegate do_determine_auth_method_for_mpi(person, chageset), to: V1Creator
  defdelegate validate_employee_speciality(employee), to: V1Creator
  defdelegate validate_employee_status(employee), to: V1Creator
  defdelegate check_phone_number_auth_limit(search_result, chageset, auxiliary_entities), to: V1Creator

  defp insert_declaration_request(params, user_id, auxiliary_entities) do
    params
    |> changeset(user_id, auxiliary_entities)
    |> determine_auth_method_for_mpi(params["channel"], auxiliary_entities)
    |> generate_printout_form(auxiliary_entities[:employee])
    |> do_insert_declaration_request()
  end

  def determine_auth_method_for_mpi(%Changeset{valid?: false} = changeset, _, _), do: changeset

  def determine_auth_method_for_mpi(changeset, @channel_cabinet, auxiliary_entities) do
    changeset
    |> put_change(:authentication_method_current, %{"type" => @auth_na})
    |> put_change(:mpi_id, auxiliary_entities[:person_id])
  end

  def determine_auth_method_for_mpi(changeset, _, auxiliary_entities) do
    changeset
    |> get_field(:data)
    |> get_in(["person"])
    |> mpi_search()
    |> check_phone_number_auth_limit(changeset, auxiliary_entities)
    |> do_determine_auth_method_for_mpi(changeset)
  end

  def mpi_search(person) do
    with {:ok, search_params} <- Persons.get_search_params(person) do
      MpiSearch.search(search_params)
    end
  end
end
