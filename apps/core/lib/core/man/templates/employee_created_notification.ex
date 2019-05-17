defmodule Core.Man.Templates.EmployeeCreatedNotification do
  @moduledoc false

  use Confex, otp_app: :core

  alias Core.EmployeeRequests.EmployeeRequest, as: Request
  alias Core.LegalEntities
  alias Core.Man.Client, as: ManClient
  alias Core.Man.Templates.EmployeeRequestInvitation

  def render(%Request{id: id, data: data}) do
    clinic_info =
      data
      |> Map.get("legal_entity_id")
      |> LegalEntities.get_by_id()
      |> EmployeeRequestInvitation.get_clinic_info()

    template_data = %{
      format: config()[:format],
      locale: config()[:locale],
      date: EmployeeRequestInvitation.current_date("Europe/Kiev", "%d.%m.%y"),
      clinic_name: Map.get(clinic_info, :name),
      clinic_address: Map.get(clinic_info, :address),
      doctor_role: Map.get(data, "position"),
      request_id: id
    }

    template_id = config()[:id]

    ManClient.render_template(template_id, template_data)
  end
end
