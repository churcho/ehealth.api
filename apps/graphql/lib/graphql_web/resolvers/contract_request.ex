defmodule GraphQLWeb.Resolvers.ContractRequest do
  @moduledoc false

  import Ecto.Query, only: [where: 2, where: 3, join: 4, select: 3, order_by: 2]
  import GraphQLWeb.Resolvers.Helpers.Search, only: [filter: 2]
  import GraphQLWeb.Resolvers.Helpers.Errors, only: [format_conflict_error: 1, format_forbidden_error: 1]

  alias Absinthe.Relay.Connection
  alias Core.ContractRequests
  alias Core.ContractRequests.ContractRequest
  alias Core.Employees.Employee
  alias Core.Man.Templates.ContractRequestPrintoutForm
  alias Core.{PRMRepo, Repo}

  def list_contract_requests(args, %{context: %{client_type: "NHS"}}) do
    ContractRequest
    |> search(args)
    |> Connection.from_query(&Repo.all/1, args)
  end

  def list_contract_requests(args, %{context: %{client_type: "MSP", client_id: client_id}}) do
    ContractRequest
    |> where(contractor_legal_entity_id: ^client_id)
    |> search(args)
    |> Connection.from_query(&Repo.all/1, args)
  end

  defp search(query, %{filter: filter, order_by: order_by}) do
    filter = prepare_filter(filter)

    query
    |> filter(filter)
    |> order_by(^order_by)
  end

  defp prepare_filter([]), do: []

  defp prepare_filter([{:assignee_name, value} | tail]) do
    assignee_ids =
      Employee
      |> join(:inner, [e], p in assoc(e, :party))
      |> where([e], e.employee_type == "NHS")
      |> where(
        [..., p],
        fragment(
          "to_tsvector(concat_ws(' ', ?, ?, ?)) @@ to_tsquery(?)",
          p.last_name,
          p.first_name,
          p.second_name,
          ^value
        )
      )
      |> select([e], e.id)
      |> PRMRepo.all()

    [{:assignee_id, assignee_ids} | prepare_filter(tail)]
  end

  defp prepare_filter([head | tail]), do: [head | prepare_filter(tail)]

  def get_printout_content(%ContractRequest{} = contract_request, _args, %{context: context}) do
    contract_request = Map.put(contract_request, :nhs_signed_date, Date.utc_today())

    with :ok <- ContractRequests.validate_status(contract_request, ContractRequest.status(:pending_nhs_sign)),
         # todo: causes N+1 problem with DB query and man templace rendening
         {:ok, printout_content} <- ContractRequestPrintoutForm.render(contract_request, context.headers) do
      {:ok, printout_content}
    else
      {:error, {:conflict, error}} -> {:error, format_conflict_error(error)}
      {:error, {:forbidden, error}} -> {:error, format_forbidden_error(error)}
      error -> error
    end
  end
end
