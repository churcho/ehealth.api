defmodule GraphQL.Resolvers.Task do
  @moduledoc false

  import GraphQL.Resolvers.Helpers.Load, only: [load_by_parent_with_connection: 5]
  alias GraphQL.Loaders.Jabba

  def load_tasks(parent, args, resolution) do
    load_by_parent_with_connection(parent, args, resolution, {:search_tasks, :many, :job_id}, Jabba)
  end
end
