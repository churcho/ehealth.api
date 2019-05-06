defmodule Core.Registers.Register do
  @moduledoc false

  use Ecto.Schema

  @new "NEW"
  @processed "PROCESSED"
  @invalid "INVALID"

  @death "death_registration"

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "registers" do
    field(:file_name, :string)
    field(:type, :string, null: false)
    field(:entity_type, :string, null: false)
    field(:status, :string, default: @new)
    field(:errors, {:array, :string})
    field(:inserted_by, Ecto.UUID, null: false)
    field(:updated_by, Ecto.UUID)

    embeds_one :qty, Qty, primary_key: false, on_replace: :delete do
      field(:total, :integer, default: 0)
      field(:errors, :integer, default: 0)
      field(:not_found, :integer, default: 0)
      field(:processed, :integer, default: 0)
    end

    has_many(:register_entries, Core.Registers.RegisterEntry)

    timestamps(type: :utc_datetime_usec)
  end

  def type(:death), do: @death

  def status(:new), do: @new
  def status(:processed), do: @processed
  def status(:invalid), do: @invalid
end
