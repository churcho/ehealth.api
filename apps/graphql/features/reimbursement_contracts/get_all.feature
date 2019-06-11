Feature: Get all reimbursement contracts

  Scenario: Request all items with NHS client
    Given there are 2 reimbursement contracts exist
    And there are 10 capitation contracts exist
    And my scope is "contract:read"
    And my client type is "NHS"
    When I request first 10 reimbursement contracts
    Then no errors should be returned
    And I should receive collection with 2 items

  Scenario: Request belonging items with PHARMACY client
    Given the following legal entities exist:
      | databaseId                             | type  |
      | "eeca6674-5d4b-4351-887b-901d379e8d7a" | "PHARMACY" |
      | "c26c6f9a-de97-45d4-abf2-017dd25a40e0" | "PHARMACY" |
    And the following reimbursement contracts are associated with legal entities accordingly:
      | databaseId                             |
      | "81a27fee-7ecd-4c9d-ab47-2c085a711cc4" |
      | "5f8362d2-36bc-4de2-9e8c-278897b8edb6" |
    And my scope is "contract:read"
    And my client type is "PHARMACY"
    And my client ID is "eeca6674-5d4b-4351-887b-901d379e8d7a"
    When I request first 10 reimbursement contracts
    Then no errors should be returned
    And I should receive collection with 1 item
    And the databaseId of the first item in the collection should be "81a27fee-7ecd-4c9d-ab47-2c085a711cc4"

  Scenario: Request with incorrect client
    Given there are 2 reimbursement contracts exist
    And my scope is "contract:read"
    And my client type is "MIS"
    When I request first 10 reimbursement contracts
    Then the "FORBIDDEN" error should be returned
    And I should not receive any collection items

  Scenario Outline: Request items filtered by condition
    Given the following reimbursement contracts exist:
      | <field>           |
      | <alternate_value> |
      | <expected_value>  |
    And my scope is "contract:read"
    And my client type is "NHS"
    When I request first 10 reimbursement contracts where <field> is <filter_value>
    Then no errors should be returned
    And I should receive collection with 1 item
    And the <field> of the first item in the collection should be <expected_value>

    Examples:
      | field               | filter_value                           | expected_value                         | alternate_value                        |
      | databaseId          | "d4e60768-f48f-4947-b1f4-ae08a248cbd8" | "d4e60768-f48f-4947-b1f4-ae08a248cbd8" | "8e6440c2-dcb6-4f7d-9624-92c44d86f68e" |
      | contractNumber      | "0000-ABEK-1234-5678"                  | "0000-ABEK-1234-5678"                  | "0000-MHPC-8765-4321"                  |
      | status              | "VERIFIED"                             | "VERIFIED"                             | "TERMINATED"                           |
      | startDate           | "2018-05-23/2018-10-15"                | "2018-07-12"                           | "2018-11-22"                           |
      | endDate             | "2018-05-23/2018-10-15"                | "2018-07-12"                           | "2018-11-22"                           |
      | isSuspended         | false                                  | false                                  | true                                   |

  Scenario Outline: Request items filtered by condition on association
    Given the following <association_entity> exist:
      | <field>           |
      | <alternate_value> |
      | <expected_value>  |
    And the following reimbursement contracts are associated with <association_entity> accordingly:
      | databaseId     |
      | <alternate_id> |
      | <expected_id>  |
    And my scope is "contract:read"
    And my client type is "NHS"
    When I request first 10 reimbursement contracts where <field> of the associated <association_field> is <filter_value>
    Then no errors should be returned
    And I should receive collection with 1 item
    And the databaseId of the first item in the collection should be <expected_id>

    Examples:
      | association_entity | association_field     | field        | filter_value                           | expected_value                         | alternate_value                        | expected_id                            | alternate_id                           |
      | legal entities     | contractorLegalEntity | databaseId   | "02d4d9d3-f498-4ec0-a0c4-70d85f88bbdf" | "02d4d9d3-f498-4ec0-a0c4-70d85f88bbdf" | "88ef2a75-8f38-4bcd-84fb-358ed1585d41" | "6d043c09-c70c-465d-a2ae-d932a3f66195" | "15852a31-2c9f-46b9-a44a-0574b39b8978" |
      | legal entities     | contractorLegalEntity | nhsReviewed  | false                                  | false                                  | true                                   | "5e75cae7-3881-48b7-b881-5361935d3d35" | "85cb9c86-ac7a-44f6-9984-f96bbaec9934" |
      | legal entities     | contractorLegalEntity | nhsVerified  | true                                   | true                                   | false                                  | "6cb36d34-be4e-4f34-80b5-313ab086e8fa" | "2912a791-eae3-4907-81a2-bfcd3b765263" |
      | legal entities     | contractorLegalEntity | edrpou       | "12345"                                | "1234567890"                           | "0987654321"                           | "405e1669-6243-456b-b904-fe9280268ee8" | "29a6641c-6ad0-4cbc-9261-bb6267339d02" |
      | medical programs   | medicalProgram        | databaseId   | "85889112-ceac-443b-9c83-440fd6a3c1d6" | "85889112-ceac-443b-9c83-440fd6a3c1d6" | "89753ca9-1b58-4454-a30e-a1f5650be4b3" | "c6a2d8bc-c712-4457-970a-69ab53e19424" | "04cf7b31-a84e-4ef4-ab22-64badf2ab343" |
      | medical programs   | medicalProgram        | name         | "ліки"                                 | "Доступні ліки"                        | "Безкоштовні вакцини"                  | "c70e7f96-b579-4e4b-be59-3612ad3d0388" | "f0076dbf-c5b5-4f61-8c75-2d0c60a468da" |
      | medical programs   | medicalProgram        | isActive     | true                                   | true                                   | false                                  | "2fe64239-4ba4-4297-acef-698a0910680a" | "0fde198f-0bc2-4845-bb01-a84c3e620398" |

  Scenario Outline: Request items ordered by field values
    Given the following reimbursement contracts exist:
      | <field>           |
      | <alternate_value> |
      | <expected_value>  |
    And my scope is "contract:read"
    And my client type is "NHS"
    When I request first 10 reimbursement contracts sorted by <field> in <direction> order
    Then no errors should be returned
    And I should receive collection with 2 items
    And the <field> of the first item in the collection should be <expected_value>

    Examples:
      | field       | direction  | expected_value                | alternate_value               |
      | endDate     | ascending  | "2018-07-12"                  | "2018-11-22"                  |
      | endDate     | descending | "2018-11-22"                  | "2018-07-12"                  |
      | insertedAt  | ascending  | "2016-01-15T14:00:00.000000Z" | "2017-05-13T17:00:00.000000Z" |
      | insertedAt  | descending | "2017-05-13T17:00:00.000000Z" | "2016-01-15T14:00:00.000000Z" |
      | isSuspended | ascending  | false                         | true                          |
      | isSuspended | descending | true                          | false                         |
      | startDate   | ascending  | "2016-08-01"                  | "2016-10-30"                  |
      | startDate   | descending | "2016-10-30"                  | "2016-08-01"                  |
      | status      | ascending  | "TERMINATED"                  | "VERIFIED"                    |
      | status      | descending | "VERIFIED"                    | "TERMINATED"                  |
