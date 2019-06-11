defmodule EHealth.Web.MedicationRequestView do
  @moduledoc false

  use EHealth.Web, :view
  alias Core.MedicationRequests.Renderer, as: MedicationRequestsRenderer

  def render("index.json", %{medication_requests: medication_requests}) do
    render_many(medication_requests, __MODULE__, "show.json")
  end

  def render("show.json", %{medication_request: medication_request}) do
    MedicationRequestsRenderer.render("show.json", medication_request)
  end

  def render("qualify.json", %{medical_programs: medical_programs, validations: validations}) do
    Enum.map(medical_programs, fn program ->
      {_, validation} = Enum.find(validations, fn {id, _} -> id == program.id end)

      {status, reason, participants} =
        case validation do
          :ok ->
            {"VALID", "",
             render_many(
               program.program_medications,
               __MODULE__,
               "program_medication.json",
               as: :program_medication
             )}

          {:error, reason} ->
            {"INVALID", reason, []}
        end

      %{
        "program_id" => program.id,
        "program_name" => program.name,
        "status" => status,
        "rejection_reason" => reason,
        "participants" => participants
      }
    end)
  end

  def render("program_medication.json", %{program_medication: program_medication}) do
    medication = program_medication.medication

    %{
      "id" => program_medication.id,
      "medication_id" => medication.id,
      "medication_name" => medication.name,
      "form" => medication.form,
      "manufacturer" => medication.manufacturer,
      "package_qty" => medication.package_qty,
      "package_min_qty" => medication.package_min_qty,
      "reimbursement_amount" => program_medication.reimbursement.reimbursement_amount,
      "wholesale_price" => program_medication.wholesale_price,
      "consumer_price" => program_medication.consumer_price,
      "reimbursement_daily_dosage" => program_medication.reimbursement_daily_dosage,
      "estimated_payment_amount" => program_medication.estimated_payment_amount,
      "start_date" => program_medication.start_date,
      "end_date" => program_medication.end_date,
      "registry_number" => program_medication.registry_number
    }
  end
end
