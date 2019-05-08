Feature: Get specific capitation contract

  Scenario: Get toCreateRequestContent field
    Given the following legal entities exist:
      | databaseId                             | type  |
      | "6696a798-22a7-4670-97b4-3b7d274f2d11" | "NHS" |
      | "e8d4b752-79e7-4906-835f-42397ac78b56" | "MSP" |
    And the following employees are associated with legal entities accordingly:
      | databaseId                             | employeeType |
      | "2c5ef867-310e-42f4-a581-27613e3ac2aa" | "NHS_SIGNER" |
      | "f8feba9f-216d-4caf-bbaa-4228505351ad" | "OWNER"      |
    And the following divisions exist:
      | databaseId                             | type     | legalEntityId                          |
      | "47e56ff3-75ae-416b-8d35-4b4a8409e3c0" | "CLINIC" | "e8d4b752-79e7-4906-835f-42397ac78b56" |
      | "0ffa3a6e-12d8-40d8-8c60-ee7bcd7ef32f" | "CLINIC" | "e8d4b752-79e7-4906-835f-42397ac78b56" |
    And the following employees exist:
      | databaseId                             | employeeType | legalEntityId                          |
      | "59c88952-ce62-47b9-b400-3a26ccde0cc9" | "DOCTOR"     | "e8d4b752-79e7-4906-835f-42397ac78b56" |
      | "9071e3b7-1468-4322-8742-c3ccd571ef65" | "DOCTOR"     | "e8d4b752-79e7-4906-835f-42397ac78b56" |
    And a capitation contract with the following fields exist:
      | field                    | value                                                                             |
      | databaseId               | "8b9482fe-6cb6-4855-a923-7ccd4d9b7aef"                                            |
      | contractNumber           | "0000-9EAX-XT7X-3115"                                                             |
      | contractorLegalEntityId  | "e8d4b752-79e7-4906-835f-42397ac78b56"                                            |
      | contractorOwnerId        | "f8feba9f-216d-4caf-bbaa-4228505351ad"                                            |
      | contractorPaymentDetails | {"MFO": "351005", "bank_name": "Банк номер 1", "payer_account": "32009102701026"} |
      | contractorRmspAmount     | 58813                                                                             |
      | endDate                  | "2019-04-11"                                                                      |
      | externalContractorFlag   | false                                                                             |
      | externalContractors      | null                                                                              |
      | idForm                   | "17"                                                                              |
      | issueCity                | "Київ"                                                                            |
      | nhsContractPrice         | 105938.0                                                                          |
      | nhsLegalEntityId         | "6696a798-22a7-4670-97b4-3b7d274f2d11"                                            |
      | nhsPaymentMethod         | "prepayment"                                                                      |
      | nhsSignerBase            | "на підставі наказу"                                                              |
      | nhsSignerId              | "2c5ef867-310e-42f4-a581-27613e3ac2aa"                                            |
      | startDate                | "2019-03-28"                                                                      |
    And the following contract divisions exist:
      | contractId                             | divisionId                             |
      | "8b9482fe-6cb6-4855-a923-7ccd4d9b7aef" | "47e56ff3-75ae-416b-8d35-4b4a8409e3c0" |
      | "8b9482fe-6cb6-4855-a923-7ccd4d9b7aef" | "0ffa3a6e-12d8-40d8-8c60-ee7bcd7ef32f" |
    And the following contract employees exist:
      | contractId                             | employeeId                             | divisionId                             | declarationLimit | staffUnits |
      | "8b9482fe-6cb6-4855-a923-7ccd4d9b7aef" | "59c88952-ce62-47b9-b400-3a26ccde0cc9" | "47e56ff3-75ae-416b-8d35-4b4a8409e3c0" | 2000             | 123.0      |
      | "8b9482fe-6cb6-4855-a923-7ccd4d9b7aef" | "9071e3b7-1468-4322-8742-c3ccd571ef65" | "0ffa3a6e-12d8-40d8-8c60-ee7bcd7ef32f" | 2000             | 123.0      |
    And the following dictionaries exist:
      | name                               | values                                                                                                         | isActive |
      | "CAPITATION_CONTRACT_CONSENT_TEXT" | {"APPROVED": "Цією заявою Заявник висловлює бажання укласти договір про медичне обслуговування населення..." } | true     |
    And my scope is "contract:read"
    And my client type is "NHS"
    And my client ID is "6696a798-22a7-4670-97b4-3b7d274f2d11"
    When I request toCreateRequestContent of the capitation contract where databaseId is "8b9482fe-6cb6-4855-a923-7ccd4d9b7aef"
    Then no errors should be returned
    And I should receive requested item
    And the toCreateRequestContent of the requested item should have the following fields:
      | field                         | value                                                                                                                                                                                                                                                                                                                              |
      | consent_text                  | "Цією заявою Заявник висловлює бажання укласти договір про медичне обслуговування населення..."                                                                                                                                                                                                                                    |
      | contract_number               | "0000-9EAX-XT7X-3115"                                                                                                                                                                                                                                                                                                              |
      | contractor_base               | "на підставі закону про Медичне обслуговування населення"                                                                                                                                                                                                                                                                          |
      | contractor_divisions          | ["47e56ff3-75ae-416b-8d35-4b4a8409e3c0", "0ffa3a6e-12d8-40d8-8c60-ee7bcd7ef32f"]                                                                                                                                                                                                                                                   |
      | contractor_employee_divisions | [{"declaration_limit": 2000, "division_id": "47e56ff3-75ae-416b-8d35-4b4a8409e3c0", "employee_id": "59c88952-ce62-47b9-b400-3a26ccde0cc9", "staff_units": 123.0}, {"declaration_limit": 2000, "division_id": "0ffa3a6e-12d8-40d8-8c60-ee7bcd7ef32f", "employee_id": "9071e3b7-1468-4322-8742-c3ccd571ef65", "staff_units": 123.0}] |
      | contractor_legal_entity_id    | "e8d4b752-79e7-4906-835f-42397ac78b56"                                                                                                                                                                                                                                                                                             |
      | contractor_owner_id           | "f8feba9f-216d-4caf-bbaa-4228505351ad"                                                                                                                                                                                                                                                                                             |
      | contractor_payment_details    | {"MFO": "351005", "bank_name": "Банк номер 1", "payer_account": "32009102701026"}                                                                                                                                                                                                                                                  |
      | contractor_rmsp_amount        | 58813                                                                                                                                                                                                                                                                                                                              |
      | external_contractor_flag      | false                                                                                                                                                                                                                                                                                                                              |
      | id_form                       | "17"                                                                                                                                                                                                                                                                                                                               |
      | issue_city                    | "Київ"                                                                                                                                                                                                                                                                                                                             |
      | nhs_contract_price            | 105938.0                                                                                                                                                                                                                                                                                                                           |
      | nhs_legal_entity_id           | "6696a798-22a7-4670-97b4-3b7d274f2d11"                                                                                                                                                                                                                                                                                             |
      | nhs_payment_method            | "prepayment"                                                                                                                                                                                                                                                                                                                       |
      | nhs_signer_base               | "на підставі наказу"                                                                                                                                                                                                                                                                                                               |
      | nhs_signer_id                 | "2c5ef867-310e-42f4-a581-27613e3ac2aa"                                                                                                                                                                                                                                                                                             |
      | parent_contract_id            | "8b9482fe-6cb6-4855-a923-7ccd4d9b7aef"                                                                                                                                                                                                                                                                                             |

  Scenario: Get toCreateRequestContent field with external contractors
    Given the following legal entities exist:
      | databaseId                             | type  |
      | "6696a798-22a7-4670-97b4-3b7d274f2d11" | "NHS" |
      | "e8d4b752-79e7-4906-835f-42397ac78b56" | "MSP" |
    And the following employees are associated with legal entities accordingly:
      | databaseId                             | employeeType |
      | "2c5ef867-310e-42f4-a581-27613e3ac2aa" | "NHS_SIGNER" |
      | "f8feba9f-216d-4caf-bbaa-4228505351ad" | "OWNER"      |
    And the following divisions exist:
      | databaseId                             | type     | legalEntityId                          |
      | "47e56ff3-75ae-416b-8d35-4b4a8409e3c0" | "CLINIC" | "e8d4b752-79e7-4906-835f-42397ac78b56" |
      | "0ffa3a6e-12d8-40d8-8c60-ee7bcd7ef32f" | "CLINIC" | "e8d4b752-79e7-4906-835f-42397ac78b56" |
    And the following employees exist:
      | databaseId                             | employeeType | legalEntityId                          |
      | "59c88952-ce62-47b9-b400-3a26ccde0cc9" | "DOCTOR"     | "e8d4b752-79e7-4906-835f-42397ac78b56" |
      | "9071e3b7-1468-4322-8742-c3ccd571ef65" | "DOCTOR"     | "e8d4b752-79e7-4906-835f-42397ac78b56" |
    And a capitation contract with the following fields exist:
      | field                    | value                                                                                                                                                                                                                                                                                                                                        |
      | databaseId               | "8b9482fe-6cb6-4855-a923-7ccd4d9b7aef"                                                                                                                                                                                                                                                                                                       |
      | contractNumber           | "0000-9EAX-XT7X-3115"                                                                                                                                                                                                                                                                                                                        |
      | contractorLegalEntityId  | "e8d4b752-79e7-4906-835f-42397ac78b56"                                                                                                                                                                                                                                                                                                       |
      | contractorOwnerId        | "f8feba9f-216d-4caf-bbaa-4228505351ad"                                                                                                                                                                                                                                                                                                       |
      | contractorPaymentDetails | {"MFO": "351005", "bank_name": "Банк номер 1", "payer_account": "32009102701026"}                                                                                                                                                                                                                                                            |
      | contractorRmspAmount     | 58813                                                                                                                                                                                                                                                                                                                                        |
      | endDate                  | "2019-04-11"                                                                                                                                                                                                                                                                                                                                 |
      | externalContractorFlag   | true                                                                                                                                                                                                                                                                                                                                         |
      | externalContractors      | [{"contract": {"expires_at": "2020-03-27T11:53:29.256703", "issued_at": "2019-03-28T11:53:29.256701", "number": "1234567"}, "divisions": [{"id": "8256845e-b670-4869-a698-df45854aaa54", "medical_service": "Послуга ПМД", "name": "Бориспільське відділення Клініки Ноунейм"}], "legal_entity_id": "d5a85ff9-c574-4df2-a932-d4b9fa0c7ae6"}] |
      | idForm                   | "17"                                                                                                                                                                                                                                                                                                                                         |
      | issueCity                | "Київ"                                                                                                                                                                                                                                                                                                                                       |
      | nhsContractPrice         | 105938.0                                                                                                                                                                                                                                                                                                                                     |
      | nhsLegalEntityId         | "6696a798-22a7-4670-97b4-3b7d274f2d11"                                                                                                                                                                                                                                                                                                       |
      | nhsPaymentMethod         | "prepayment"                                                                                                                                                                                                                                                                                                                                 |
      | nhsSignerBase            | "на підставі наказу"                                                                                                                                                                                                                                                                                                                         |
      | nhsSignerId              | "2c5ef867-310e-42f4-a581-27613e3ac2aa"                                                                                                                                                                                                                                                                                                       |
      | startDate                | "2019-03-28"                                                                                                                                                                                                                                                                                                                                 |
    And the following contract divisions exist:
      | contractId                             | divisionId                             |
      | "8b9482fe-6cb6-4855-a923-7ccd4d9b7aef" | "47e56ff3-75ae-416b-8d35-4b4a8409e3c0" |
      | "8b9482fe-6cb6-4855-a923-7ccd4d9b7aef" | "0ffa3a6e-12d8-40d8-8c60-ee7bcd7ef32f" |
    And the following contract employees exist:
      | contractId                             | employeeId                             | divisionId                             | declarationLimit | staffUnits |
      | "8b9482fe-6cb6-4855-a923-7ccd4d9b7aef" | "59c88952-ce62-47b9-b400-3a26ccde0cc9" | "47e56ff3-75ae-416b-8d35-4b4a8409e3c0" | 2000             | 123.0      |
      | "8b9482fe-6cb6-4855-a923-7ccd4d9b7aef" | "9071e3b7-1468-4322-8742-c3ccd571ef65" | "0ffa3a6e-12d8-40d8-8c60-ee7bcd7ef32f" | 2000             | 123.0      |
    And the following dictionaries exist:
      | name                               | values                                                                                                         | isActive |
      | "CAPITATION_CONTRACT_CONSENT_TEXT" | {"APPROVED": "Цією заявою Заявник висловлює бажання укласти договір про медичне обслуговування населення..." } | true     |
    And my scope is "contract:read"
    And my client type is "NHS"
    And my client ID is "6696a798-22a7-4670-97b4-3b7d274f2d11"
    When I request toCreateRequestContent of the capitation contract where databaseId is "8b9482fe-6cb6-4855-a923-7ccd4d9b7aef"
    Then no errors should be returned
    And I should receive requested item
    And the toCreateRequestContent of the requested item should have the following fields:
      | field                         | value                                                                                                                                                                                                                                                                                                                                        |
      | consent_text                  | "Цією заявою Заявник висловлює бажання укласти договір про медичне обслуговування населення..."                                                                                                                                                                                                                                              |
      | contract_number               | "0000-9EAX-XT7X-3115"                                                                                                                                                                                                                                                                                                                        |
      | contractor_base               | "на підставі закону про Медичне обслуговування населення"                                                                                                                                                                                                                                                                                    |
      | contractor_divisions          | ["47e56ff3-75ae-416b-8d35-4b4a8409e3c0", "0ffa3a6e-12d8-40d8-8c60-ee7bcd7ef32f"]                                                                                                                                                                                                                                                             |
      | contractor_employee_divisions | [{"declaration_limit": 2000, "division_id": "47e56ff3-75ae-416b-8d35-4b4a8409e3c0", "employee_id": "59c88952-ce62-47b9-b400-3a26ccde0cc9", "staff_units": 123.0}, {"declaration_limit": 2000, "division_id": "0ffa3a6e-12d8-40d8-8c60-ee7bcd7ef32f", "employee_id": "9071e3b7-1468-4322-8742-c3ccd571ef65", "staff_units": 123.0}]           |
      | contractor_legal_entity_id    | "e8d4b752-79e7-4906-835f-42397ac78b56"                                                                                                                                                                                                                                                                                                       |
      | contractor_owner_id           | "f8feba9f-216d-4caf-bbaa-4228505351ad"                                                                                                                                                                                                                                                                                                       |
      | contractor_payment_details    | {"MFO": "351005", "bank_name": "Банк номер 1", "payer_account": "32009102701026"}                                                                                                                                                                                                                                                            |
      | contractor_rmsp_amount        | 58813                                                                                                                                                                                                                                                                                                                                        |
      | external_contractor_flag      | true                                                                                                                                                                                                                                                                                                                                         |
      | external_contractors          | [{"contract": {"expires_at": "2020-03-27T11:53:29.256703", "issued_at": "2019-03-28T11:53:29.256701", "number": "1234567"}, "divisions": [{"id": "8256845e-b670-4869-a698-df45854aaa54", "medical_service": "Послуга ПМД", "name": "Бориспільське відділення Клініки Ноунейм"}], "legal_entity_id": "d5a85ff9-c574-4df2-a932-d4b9fa0c7ae6"}] |
      | id_form                       | "17"                                                                                                                                                                                                                                                                                                                                         |
      | issue_city                    | "Київ"                                                                                                                                                                                                                                                                                                                                       |
      | nhs_contract_price            | 105938.0                                                                                                                                                                                                                                                                                                                                     |
      | nhs_legal_entity_id           | "6696a798-22a7-4670-97b4-3b7d274f2d11"                                                                                                                                                                                                                                                                                                       |
      | nhs_payment_method            | "prepayment"                                                                                                                                                                                                                                                                                                                                 |
      | nhs_signer_base               | "на підставі наказу"                                                                                                                                                                                                                                                                                                                         |
      | nhs_signer_id                 | "2c5ef867-310e-42f4-a581-27613e3ac2aa"                                                                                                                                                                                                                                                                                                       |
      | parent_contract_id            | "8b9482fe-6cb6-4855-a923-7ccd4d9b7aef"                                                                                                                                                                                                                                                                                                       |

  Scenario: Get toCreateRequestContent field with overdue employees
    Given the following legal entities exist:
      | databaseId                             | type  |
      | "6696a798-22a7-4670-97b4-3b7d274f2d11" | "NHS" |
      | "e8d4b752-79e7-4906-835f-42397ac78b56" | "MSP" |
    And the following employees are associated with legal entities accordingly:
      | databaseId                             | employeeType |
      | "2c5ef867-310e-42f4-a581-27613e3ac2aa" | "NHS_SIGNER" |
      | "f8feba9f-216d-4caf-bbaa-4228505351ad" | "OWNER"      |
    And the following divisions exist:
      | databaseId                             | type     | legalEntityId                          |
      | "47e56ff3-75ae-416b-8d35-4b4a8409e3c0" | "CLINIC" | "e8d4b752-79e7-4906-835f-42397ac78b56" |
      | "0ffa3a6e-12d8-40d8-8c60-ee7bcd7ef32f" | "CLINIC" | "e8d4b752-79e7-4906-835f-42397ac78b56" |
    And the following employees exist:
      | databaseId                             | employeeType | legalEntityId                          |
      | "59c88952-ce62-47b9-b400-3a26ccde0cc9" | "DOCTOR"     | "e8d4b752-79e7-4906-835f-42397ac78b56" |
      | "9071e3b7-1468-4322-8742-c3ccd571ef65" | "DOCTOR"     | "e8d4b752-79e7-4906-835f-42397ac78b56" |
    And a capitation contract with the following fields exist:
      | field                    | value                                                                             |
      | databaseId               | "8b9482fe-6cb6-4855-a923-7ccd4d9b7aef"                                            |
      | contractNumber           | "0000-9EAX-XT7X-3115"                                                             |
      | contractorLegalEntityId  | "e8d4b752-79e7-4906-835f-42397ac78b56"                                            |
      | contractorOwnerId        | "f8feba9f-216d-4caf-bbaa-4228505351ad"                                            |
      | contractorPaymentDetails | {"MFO": "351005", "bank_name": "Банк номер 1", "payer_account": "32009102701026"} |
      | contractorRmspAmount     | 58813                                                                             |
      | endDate                  | "2019-04-11"                                                                      |
      | externalContractorFlag   | false                                                                             |
      | externalContractors      | null                                                                              |
      | idForm                   | "17"                                                                              |
      | issueCity                | "Київ"                                                                            |
      | nhsContractPrice         | 105938.0                                                                          |
      | nhsLegalEntityId         | "6696a798-22a7-4670-97b4-3b7d274f2d11"                                            |
      | nhsPaymentMethod         | "prepayment"                                                                      |
      | nhsSignerBase            | "на підставі наказу"                                                              |
      | nhsSignerId              | "2c5ef867-310e-42f4-a581-27613e3ac2aa"                                            |
      | startDate                | "2019-03-28"                                                                      |
    And the following contract divisions exist:
      | contractId                             | divisionId                             |
      | "8b9482fe-6cb6-4855-a923-7ccd4d9b7aef" | "47e56ff3-75ae-416b-8d35-4b4a8409e3c0" |
      | "8b9482fe-6cb6-4855-a923-7ccd4d9b7aef" | "0ffa3a6e-12d8-40d8-8c60-ee7bcd7ef32f" |
    And the following contract employees exist:
      | contractId                             | employeeId                             | divisionId                             | declarationLimit | staffUnits | startDate                     | endDate                       |
      | "8b9482fe-6cb6-4855-a923-7ccd4d9b7aef" | "59c88952-ce62-47b9-b400-3a26ccde0cc9" | "47e56ff3-75ae-416b-8d35-4b4a8409e3c0" | 2000             | 123.0      | "2019-04-01T00:00:00.000000Z" | null                          |
      | "8b9482fe-6cb6-4855-a923-7ccd4d9b7aef" | "9071e3b7-1468-4322-8742-c3ccd571ef65" | "0ffa3a6e-12d8-40d8-8c60-ee7bcd7ef32f" | 2000             | 123.0      | "2019-04-01T00:00:00.000000Z" | "2020-04-01T23:59:59.999999Z" |
    And the following dictionaries exist:
      | name                               | values                                                                                                         | isActive |
      | "CAPITATION_CONTRACT_CONSENT_TEXT" | {"APPROVED": "Цією заявою Заявник висловлює бажання укласти договір про медичне обслуговування населення..." } | true     |
    And my scope is "contract:read"
    And my client type is "NHS"
    And my client ID is "6696a798-22a7-4670-97b4-3b7d274f2d11"
    When I request toCreateRequestContent of the capitation contract where databaseId is "8b9482fe-6cb6-4855-a923-7ccd4d9b7aef"
    Then no errors should be returned
    And I should receive requested item
    And the toCreateRequestContent of the requested item should have the following fields:
      | field                         | value                                                                                                                                                             |
      | consent_text                  | "Цією заявою Заявник висловлює бажання укласти договір про медичне обслуговування населення..."                                                                   |
      | contract_number               | "0000-9EAX-XT7X-3115"                                                                                                                                             |
      | contractor_base               | "на підставі закону про Медичне обслуговування населення"                                                                                                         |
      | contractor_divisions          | ["47e56ff3-75ae-416b-8d35-4b4a8409e3c0", "0ffa3a6e-12d8-40d8-8c60-ee7bcd7ef32f"]                                                                                  |
      | contractor_employee_divisions | [{"declaration_limit": 2000, "division_id": "47e56ff3-75ae-416b-8d35-4b4a8409e3c0", "employee_id": "59c88952-ce62-47b9-b400-3a26ccde0cc9", "staff_units": 123.0}] |
      | contractor_legal_entity_id    | "e8d4b752-79e7-4906-835f-42397ac78b56"                                                                                                                            |
      | contractor_owner_id           | "f8feba9f-216d-4caf-bbaa-4228505351ad"                                                                                                                            |
      | contractor_payment_details    | {"MFO": "351005", "bank_name": "Банк номер 1", "payer_account": "32009102701026"}                                                                                 |
      | contractor_rmsp_amount        | 58813                                                                                                                                                             |
      | external_contractor_flag      | false                                                                                                                                                             |
      | id_form                       | "17"                                                                                                                                                              |
      | issue_city                    | "Київ"                                                                                                                                                            |
      | nhs_contract_price            | 105938.0                                                                                                                                                          |
      | nhs_legal_entity_id           | "6696a798-22a7-4670-97b4-3b7d274f2d11"                                                                                                                            |
      | nhs_payment_method            | "prepayment"                                                                                                                                                      |
      | nhs_signer_base               | "на підставі наказу"                                                                                                                                              |
      | nhs_signer_id                 | "2c5ef867-310e-42f4-a581-27613e3ac2aa"                                                                                                                            |
      | parent_contract_id            | "8b9482fe-6cb6-4855-a923-7ccd4d9b7aef"                                                                                                                            |
