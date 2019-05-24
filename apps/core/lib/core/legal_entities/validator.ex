defmodule Core.LegalEntities.Validator do
  @moduledoc """
  Request, TaxID, Digital signature validators
  """

  import Ecto.Changeset

  alias Core.Email.Sanitizer
  alias Core.LegalEntities.LegalEntity
  alias Core.ValidationError
  alias Core.Validators.Addresses
  alias Core.Validators.BirthDate
  alias Core.Validators.Error
  alias Core.Validators.JsonObjects
  alias Core.Validators.JsonSchema
  alias Core.Validators.KVEDs
  alias Core.Validators.Signature, as: SignatureValidator
  alias Core.Validators.TaxID

  @msp LegalEntity.type(:msp)
  @pharmacy LegalEntity.type(:pharmacy)

  @rpc_worker Application.get_env(:core, :rpc_worker)

  def decode_and_validate(params, headers) do
    with :ok <- JsonSchema.validate(:legal_entity_sign, params),
         {_, {:ok, %{"content" => content, "signers" => [signer]}}} <-
           {:signed_content,
            SignatureValidator.validate(
              params["signed_legal_entity_request"],
              params["signed_content_encoding"],
              headers
            )},
         :ok <- JsonSchema.validate(:legal_entity, content),
         content = lowercase_emails(content),
         :ok <- validate_json_objects(content),
         :ok <- validate_type(content),
         :ok <- validate_pharmacy_license_number(content),
         :ok <- validate_kveds(content),
         :ok <- validate_addresses(content),
         :ok <- validate_tax_id(content),
         :ok <- validate_owner_birth_date(content),
         :ok <- validate_owner_position(content),
         {:ok, legal_entity_code} <- validate_state_registry_number(content, signer) do
      {:ok, content, legal_entity_code}
    else
      {:signed_content, {:error, {:bad_request, reason}}} ->
        Error.dump(%ValidationError{description: reason, path: "$.signed_legal_entity_request"})

      {:signed_content, {:error, %{"error" => %{"message" => reason}}}} ->
        Error.dump(%ValidationError{description: reason, path: "$.signed_legal_entity_request"})

      error ->
        error
    end
  end

  def validate_json_objects(content) do
    with :ok <- JsonObjects.array_unique_by_key(content, ["addresses"], "type"),
         :ok <- JsonObjects.array_unique_by_key(content, ["phones"], "type"),
         :ok <- JsonObjects.array_unique_by_key(content, ["owner", "phones"], "type"),
         :ok <- JsonObjects.array_unique_by_key(content, ["owner", "documents"], "type"),
         do: :ok
  end

  defp validate_type(%{"type" => @msp}), do: :ok
  defp validate_type(%{"type" => @pharmacy}), do: :ok

  defp validate_type(_),
    do: Error.dump("Only legal_entity with type MSP or Pharmacy could be created")

  defp validate_pharmacy_license_number(%{"type" => @pharmacy} = content) do
    content
    |> get_in(~w(medical_service_provider licenses))
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {license, index}, _acc ->
      case Map.has_key?(license, "license_number") do
        true ->
          {:cont, :ok}

        _ ->
          {:halt,
           Error.dump(%ValidationError{
             description: "license_number is required for legal_entity with type \"pharmacy\"",
             path: "$.medical_service_provider.licenses.[#{index}].license_number"
           })}
      end
    end)
  end

  defp validate_pharmacy_license_number(_), do: :ok

  defp validate_kveds(content) do
    content
    |> Map.get("kveds")
    |> KVEDs.validate(content["type"])
    |> case do
      %Ecto.Changeset{valid?: false} = err -> {:error, err}
      _ -> :ok
    end
  end

  def validate_addresses(content) do
    addresses = Map.get(content, "addresses") || []
    Addresses.validate(addresses, "REGISTRATION")
  end

  def validate_tax_id(content) do
    no_tax_id = get_in(content, ["owner", "no_tax_id"])

    case no_tax_id do
      true ->
        Error.dump(%ValidationError{
          description: "'no_tax_id' must be false",
          path: "$.owner.no_tax_id"
        })

      _ ->
        content
        |> get_in(["owner", "tax_id"])
        |> TaxID.validate(%ValidationError{
          description: "invalid tax_id value",
          path: "$.owner.tax_id"
        })
    end
  end

  # EDRPOU content to EDRPOU / DRFO signer validator
  def validate_state_registry_number(content, %{"edrpou" => edrpou} = signer)
      when is_nil(edrpou) or edrpou == "",
      do: validate_state_registry_number(content, Map.delete(signer, "edrpou"))

  def validate_state_registry_number(content, %{"edrpou" => edrpou}) do
    data = %{}
    types = %{edrpou: :string}

    {data, types}
    |> cast(%{"edrpou" => content_edrpou(content)}, Map.keys(types))
    |> validate_required(Map.keys(types))
    |> validate_format(:edrpou, ~r/^[0-9]{8,10}$/)
    |> validate_inclusion(:edrpou, [edrpou], message: "EDRPOU does not match legal_entity edrpou")
    |> is_valid_content(content)
  end

  def validate_state_registry_number(content, %{"drfo" => drfo}) do
    data = %{}
    types = %{drfo: :string}

    {data, types}
    |> cast(%{"drfo" => content_edrpou(content)}, Map.keys(types))
    |> validate_required(Map.keys(types))
    |> validate_format(:drfo, ~r/^[0-9]{9,10}$|^((?![ЫЪЭЁ])([А-ЯҐЇІЄ])){2}[0-9]{6}$/ui)
    |> validate_inclusion(:drfo, [drfo], message: "DRFO does not match signer drfo")
    |> is_valid_content(content)
  end

  def validate_state_registry_number(_content, _signer) do
    Error.dump(%ValidationError{
      description: "EDRPOU and DRFO is empty in digital sign",
      path: "$.data.signatures"
    })
  end

  defp content_edrpou(content) do
    content
    |> legal_entity_edrpou()
    |> String.upcase()
  end

  defp legal_entity_edrpou(%{"edrpou" => edrpou}), do: edrpou
  defp legal_entity_edrpou(%LegalEntity{edrpou: edrpou}), do: edrpou

  defp is_valid_content(%Ecto.Changeset{valid?: true, changes: changes}, _), do: {:ok, changes}

  defp is_valid_content(changeset, _content), do: {:error, changeset}

  def validate_owner_birth_date(content) do
    content
    |> get_in(["owner", "birth_date"])
    |> BirthDate.validate()
    |> case do
      true ->
        :ok

      _ ->
        Error.dump(%ValidationError{
          description: "invalid birth_date value",
          path: "$.owner.birth_date"
        })
    end
  end

  def validate_owner_position(content) do
    conf_positions = Confex.fetch_env!(:core, __MODULE__)[:owner_positions]

    content
    |> get_in(["owner", "position"])
    |> valid_owner_position?(conf_positions)
    |> case do
      true ->
        :ok

      _ ->
        Error.dump(%ValidationError{
          description: "invalid owner position value",
          path: "$.owner.position"
        })
    end
  end

  defp valid_owner_position?(_position, nil), do: false

  defp valid_owner_position?(position, positions),
    do: Enum.any?(positions, fn x -> x == position end)

  def lowercase_emails(content) do
    email = Map.get(content, "email")
    path = ~w(owner email)
    owner_email = get_in(content, path)

    content
    |> Map.put("email", Sanitizer.sanitize(email))
    |> put_in(path, Sanitizer.sanitize(owner_email))
  end

  def validate_edr_data_fields(edr_data, legal_form, name, addresses) do
    same_legal_form? =
      legal_form == edr_data["olf_code"] ||
        (legal_form == "910" && is_nil(edr_data["olf_code"]))

    with {_, true} <- {:name, name == edr_data["names"]["display"]},
         {_, true} <- {:legal_form, same_legal_form?},
         :ok <- validate_edr_data_address(edr_data, addresses) do
      :ok
    else
      {:name, _} ->
        Error.dump(%ValidationError{
          description: "Legal entity name doesn't match with EDR data",
          path: "$.name"
        })

      {:legal_form, _} ->
        Error.dump(%ValidationError{
          description: "Legal entity legal form doesn't match with EDR data",
          path: "$.legal_form"
        })

      error ->
        error
    end
  end

  defp validate_edr_data_address(edr_data, addresses) do
    {address, i} =
      addresses
      |> Enum.with_index()
      |> Enum.find(fn {address, _} -> address["type"] == "REGISTRATION" end)

    error =
      Error.dump(%ValidationError{
        description: "Legal entity registration address doesn't match with EDR data",
        path: "$.addresses.[#{i}]"
      })

    case @rpc_worker.run("uaddresses_api", Uaddresses.Rpc, :settlement_by_id, [address["settlement_id"]]) do
      {:ok, settlement_data} ->
        validate_edr_data_koatu(error, settlement_data, edr_data)

      _ ->
        error
    end
  end

  defp validate_edr_data_koatu(_, %{koatuu: nil}, %{"address" => %{"parts" => %{"atu_code" => ""}}}) do
    :ok
  end

  defp validate_edr_data_koatu(error, %{koatuu: nil}, _), do: error

  defp validate_edr_data_koatu(error, %{koatuu: settlement_koatuu}, %{
         "address" => %{"parts" => %{"atu_code" => edr_koatuu}}
       }) do
    if String.starts_with?(edr_koatuu, String.replace_trailing(settlement_koatuu, "0", "")) do
      :ok
    else
      error
    end
  end
end
