defmodule Core.Validators.JsonSchema do
  @moduledoc """
  Validates JSON schema
  """

  use JValid
  alias Core.Validators.SchemaMapper

  use_schema(
    :email_internal_request,
    "specs/json_schemas/email/email_internal_request.json"
  )

  use_schema(
    :medication_request_request_create,
    "specs/json_schemas/medication_request_request/medication_request_request_create.json"
  )

  use_schema(
    :medication_request_request_create_generic,
    "specs/json_schemas/medication_request_request/medication_request_request_create_generic.json"
  )

  use_schema(
    :medication_request_request_create_order,
    "specs/json_schemas/medication_request_request/medication_request_request_create_order.json"
  )

  use_schema(
    :medication_request_request_create_plan,
    "specs/json_schemas/medication_request_request/medication_request_request_create_plan.json"
  )

  use_schema(
    :medication_request_request_prequalify,
    "specs/json_schemas/medication_request_request/medication_request_request_prequalify_request.json"
  )

  use_schema(
    :medication_request_request_sign,
    "specs/json_schemas/medication_request_request/medication_request_request_sign_request.json"
  )

  use_schema(
    :cabinet_declaration_request,
    "specs/json_schemas/declaration_request/declaration_request_create_online.json"
  )

  use_schema(:person, "specs/json_schemas/person/person_create_update.json")
  use_schema(:medication_dispense, "specs/json_schemas/medication_dispense/medication_dispense_create_request.json")

  use_schema(
    :medication_dispense_process,
    "specs/json_schemas/medication_dispense/medication_dispense_process_request.json"
  )

  use_schema(
    :medication_dispense_process_content,
    "specs/json_schemas/medication_dispense/medication_dispense_process_content.json"
  )

  use_schema(:medical_program, "specs/json_schemas/medical_program/medical_program_create_request.json")
  use_schema(:declaration_request, "specs/json_schemas/declaration_request/declaration_request_create_request.json")

  use_schema(
    :declaration_request_v2,
    "specs/json_schemas/declaration_request/v2/declaration_request_create_request.json"
  )

  use_schema(:division, "specs/json_schemas/division/division_create_request.json")
  use_schema(:employee_request, "specs/json_schemas/employee_request/employee_request_create_request.json")
  use_schema(:employee_request_sign, "specs/json_schemas/employee_request/employee_request_sign.json")
  use_schema(:employee_doctor, "specs/json_schemas/employee/employee_doctor_create_request.json")
  use_schema(:employee_pharmacist, "specs/json_schemas/employee/employee_pharmacist_create_request.json")
  use_schema(:employee_surgeon, "specs/json_schemas/employee/employee_surgeon_create_request.json")
  use_schema(:employee_specialist, "specs/json_schemas/employee/employee_specialist_create_request.json")
  use_schema(:legal_entity_v2, "specs/json_schemas/legal_entity/v2/legal_entity_create_request.json")
  use_schema(:legal_entity, "specs/json_schemas/legal_entity/legal_entity_create_request.json")
  use_schema(:legal_entity_sign, "specs/json_schemas/legal_entity/legal_entity_sign.json")
  use_schema(:legal_entity_merge_job, "specs/json_schemas/legal_entity/legal_entity_merge_job.json")
  use_schema(:innm, "specs/json_schemas/innm/innm_create_request.json")
  use_schema(:medication, "specs/json_schemas/medication/medication_create_request.json")
  use_schema(:innm_dosage, "specs/json_schemas/innm_dosage/innm_dosage_create_request.json")
  use_schema(:program_medication, "specs/json_schemas/program_medication/program_medication_create_request.json")
  use_schema(:program_medication_update, "specs/json_schemas/program_medication/program_medication_update_request.json")
  use_schema(:registers, "specs/json_schemas/registers/registers_create_request.json")
  use_schema(:contract_sign, "specs/json_schemas/contract/contract_sign.json")
  use_schema(:contract_prolongate, "specs/json_schemas/contract/contract_prolongate.json")
  use_schema(:contract_update_employees, "specs/json_schemas/contract/contract_update_employees.json")
  use_schema(:contract_terminate, "specs/json_schemas/contract/contract_terminate.json")
  use_schema(:service, "specs/json_schemas/service_catalog/service_create_request.json")

  # capitation contract requests
  use_schema(
    :capitation_contract_request_create_from_draft,
    "specs/json_schemas/contract_request/capitation/contract_request_create_from_draft.json"
  )

  use_schema(
    :capitation_contract_request_create_from_contract,
    "specs/json_schemas/contract_request/capitation/contract_request_create_from_contract.json"
  )

  use_schema(
    :capitation_contract_request_update,
    "specs/json_schemas/contract_request/capitation/contract_request_update.json"
  )

  # reimbursement contract requests

  use_schema(
    :reimbursement_contract_request_create_from_draft,
    "specs/json_schemas/contract_request/reimbursement/contract_request_create_from_draft.json"
  )

  use_schema(
    :reimbursement_contract_request_create_from_contract,
    "specs/json_schemas/contract_request/reimbursement/contract_request_create_from_contract.json"
  )

  use_schema(
    :reimbursement_contract_request_update,
    "specs/json_schemas/contract_request/reimbursement/contract_request_update.json"
  )

  use_schema(:contract_request_sign, "specs/json_schemas/contract_request/contract_request_sign.json")
  use_schema(:contract_request_decline, "specs/json_schemas/contract_request/contract_request_decline.json")
  use_schema(:contract_request_approve, "specs/json_schemas/contract_request/contract_request_approve.json")
  use_schema(:contract_request_assign, "specs/json_schemas/contract_request/contract_request_assign.json")

  use_schema(
    :contract_update_employees_is_active,
    "specs/json_schemas/contract/contract_update_employees_is_active.json"
  )

  use_schema(
    :medication_request_qualify,
    "specs/json_schemas/medication_request/medication_request_qualify_request.json"
  )

  use_schema(:medication_request_reject, "specs/json_schemas/medication_request/medication_request_reject_request.json")

  use_schema(
    :medication_request_reject_content_order,
    "specs/json_schemas/medication_request/medication_request_reject_content_order.json"
  )

  use_schema(
    :medication_request_reject_content_plan,
    "specs/json_schemas/medication_request/medication_request_reject_content_plan.json"
  )

  use_schema(:credentials_recovery_request, "specs/json_schemas/user/credentials_recovery_request.json")
  use_schema(:connection_update, "specs/json_schemas/connection/connection_update.json")

  def validate(schema, attrs) do
    @schemas
    |> Keyword.get(schema)
    |> SchemaMapper.prepare_schema(schema)
    |> validate_schema(attrs)
  end
end
