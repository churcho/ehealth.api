defmodule GraphQL.Middleware.ScopeAuthorization do
  @moduledoc """
  This middleware performs scope-based authorization on the fields.
  """

  @behaviour Absinthe.Middleware

  alias Absinthe.{Resolution, Type}

  defmacro __using__(opts \\ []) do
    meta_key = Keyword.get(opts, :meta_key, :scope)
    context_key = Keyword.get(opts, :context_key, :scope)

    quote do
      def middleware(middleware, field, object) do
        middleware = super(middleware, field, object)

        case Type.meta(field) do
          %{unquote(meta_key) => _} ->
            opts = [meta_key: unquote(meta_key), context_key: unquote(context_key)]
            [{unquote(__MODULE__), opts} | middleware]

          _ ->
            middleware
        end
      end

      defoverridable middleware: 3
    end
  end

  def call(%{state: :unresolved} = resolution, meta_key: meta_key, context_key: context_key) do
    requested_scope = Type.meta(resolution.definition.schema_node, meta_key)
    token_scope = Map.get(resolution.context, context_key, [])

    missing_allowances =
      [requested_scope, token_scope]
      |> Enum.map(&MapSet.new/1)
      |> (&apply(&2, &1)).(&MapSet.difference/2)
      |> MapSet.to_list()

    if Enum.empty?(missing_allowances) do
      resolution
    else
      Resolution.put_result(resolution, {:error, {:forbidden, %{missing_allowances: missing_allowances}}})
    end
  end

  def call(resolution, _), do: resolution
end
