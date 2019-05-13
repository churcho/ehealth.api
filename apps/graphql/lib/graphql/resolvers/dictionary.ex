defmodule GraphQL.Resolvers.Dictionary do
  @moduledoc false

  import GraphQL.Filters.Base, only: [filter: 2]

  alias Absinthe.Relay.Connection
  alias Core.Dictionaries
  alias Core.Dictionaries.Dictionary

  @read_repo Application.get_env(:core, :repos)[:read_repo]

  def list_dictionaries(%{filter: filter} = args, _resolution) do
    Dictionary
    |> filter(filter)
    |> Dictionaries.query_without_big_dictionaries()
    |> Connection.from_query(&@read_repo.all/1, args)
  end

  def update(%{id: id} = args, _resolution) do
    with {:ok, dictionary} <- Dictionaries.fetch_by_id(id),
         {:ok, dictionary} <- Dictionaries.update_dictionary(dictionary, args) do
      {:ok, %{dictionary: dictionary}}
    end
  end
end
