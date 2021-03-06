defmodule Core.PRMRepo.Migrations.CreateIngredients do
  use Ecto.Migration

  def change do
    alter table(:medications) do
      remove(:ingredients)
    end

    create table(:ingredients, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:dosage, :map)
      add(:is_active_substance, :boolean, default: false, null: false)

      add(:innm_id, references(:medications, type: :uuid, on_delete: :nothing), null: true)
      add(:substance_id, references(:substances, type: :uuid, on_delete: :nothing), null: true)
      add(:medication_id, references(:medications, type: :uuid, on_delete: :nothing), null: false)

      timestamps(type: :utc_datetime_usec)
    end
  end
end
