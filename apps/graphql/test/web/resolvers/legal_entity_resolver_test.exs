defmodule GraphQL.LegalEntityResolverTest do
  @moduledoc false

  use GraphQL.ConnCase, async: false

  import Core.Factories
  import Mox

  alias Absinthe.Relay.Node
  alias Core.Employees.Employee
  alias Core.LegalEntities.LegalEntity
  alias Core.PRMRepo
  alias Ecto.UUID

  @owner Employee.type(:owner)
  @doctor Employee.type(:doctor)
  @msp LegalEntity.type(:msp)
  @nhs LegalEntity.type(:nhs)

  @legal_entity_status_closed LegalEntity.status(:closed)

  @list_legal_entities_msp_query """
    query ListLegalEntitiesQuery{
      legalEntities(first: 10){
        nodes{
          license{
            orderNo
          }
          accreditation{
            category
          }
        }
      }
    }
  """

  @nhs_verify_query """
    mutation NhsVerifyLegalEntity($input: NhsVerifyLegalEntityInput!) {
      nhsVerifyLegalEntity(input: $input){
        legalEntity {
          databaseId
          status
          nhsVerified
        }
      }
    }
  """

  @nhs_review_query """
    mutation NhsReviewLegalEntity($input: NhsReviewLegalEntityInput!) {
      nhsReviewLegalEntity(input: $input){
        legalEntity {
          databaseId
          nhsReviewed
        }
      }
    }
  """

  @nhs_comment_query """
    mutation NhsCommentLegalEntity($input: NhsCommentLegalEntityInput!) {
      nhsCommentLegalEntity(input: $input){
        legalEntity {
          databaseId
          nhsComment
        }
      }
    }
  """

  setup :verify_on_exit!
  setup :set_mox_global

  setup %{conn: conn} do
    conn = put_scope(conn, "legal_entity:read legal_entity:write")

    {:ok, %{conn: conn}}
  end

  describe "list" do
    test "success without params", %{conn: conn} do
      from = insert(:prm, :legal_entity, edrpou: "1234567890")
      from2 = insert(:prm, :legal_entity, edrpou: "2234567890")
      from3 = insert(:prm, :legal_entity, edrpou: "3234567890")
      to = insert(:prm, :legal_entity)
      insert(:prm, :related_legal_entity, merged_from: from, merged_to: to)
      insert(:prm, :related_legal_entity, merged_from: from2, merged_to: to)
      insert(:prm, :related_legal_entity, merged_from: from3, merged_to: to)

      query = """
        {
          legalEntities(first: 10) {
            pageInfo {
              startCursor
              endCursor
              hasPreviousPage
              hasNextPage
            }
            nodes {
              id
              databaseId
              publicName
              mergedFromLegalEntities(first: 2, filter: {isActive: true}){
                pageInfo {
                  startCursor
                  endCursor
                  hasPreviousPage
                  hasNextPage
                }
                nodes {
                  databaseId
                  reason
                  isActive
                  mergedToLegalEntity {
                    databaseId
                    publicName
                  }
                  mergedFromLegalEntity {
                    databaseId
                    publicName
                  }
                }
              }
              mergedToLegalEntity {
                reason
                isActive
                mergedToLegalEntity {
                  databaseId
                  publicName
                }
              }
            }
          }
        }
      """

      legal_entities =
        conn
        |> post_query(query)
        |> json_response(200)
        |> get_in(~w(data legalEntities nodes))

      assert 4 == length(legal_entities)

      Enum.each(legal_entities, fn legal_entity ->
        Enum.each(~w(id publicName mergedFromLegalEntities), fn field ->
          assert Map.has_key?(legal_entity, field)
        end)
      end)
    end

    test "success with filter", %{conn: conn} do
      for edrpou <- ["1234567890", "0987654321"], do: insert(:prm, :legal_entity, edrpou: edrpou)

      query = """
        query ListLegalEntitiesQuery($first: Int!, $filter: LegalEntityFilter!) {
          legalEntities(first: $first, filter: $filter) {
            nodes {
              id
              edrpou
            }
          }
        }
      """

      variables = %{first: 10, filter: %{edrpou: "1234567890"}}

      legal_entities =
        conn
        |> post_query(query, variables)
        |> json_response(200)
        |> get_in(~w(data legalEntities nodes))

      assert 1 == length(legal_entities)
      assert "1234567890" == hd(legal_entities)["edrpou"]
    end

    test "success with filter by related legal entity edrpou", %{conn: conn} do
      from = insert(:prm, :legal_entity, edrpou: "1234567890")
      from2 = insert(:prm, :legal_entity, edrpou: "2234567890")
      insert(:prm, :legal_entity, edrpou: "3234567890")
      to = insert(:prm, :legal_entity, edrpou: "3234567899")
      insert(:prm, :related_legal_entity, merged_from: from, merged_to: to)
      related_legal_entity = insert(:prm, :related_legal_entity, merged_from: from2, merged_to: to)

      query = """
        {
          legalEntities(first: 10, filter: {edrpou: "3234567899"}) {
            nodes {
              databaseId
              mergedFromLegalEntities(
                first: 5,
                filter: {
                  mergedFromLegalEntity: {
                    edrpou: "2234567890",
                    is_active: true
                  }
                }
              ){
                nodes {
                  databaseId
                }
              }
            }
          }
        }
      """

      legal_entities =
        conn
        |> post_query(query)
        |> json_response(200)
        |> get_in(~w(data legalEntities nodes))

      assert [legal_entity] = legal_entities

      assert to.id == legal_entity["databaseId"]
      assert [%{"databaseId" => related_legal_entity.id}] == legal_entity["mergedFromLegalEntities"]["nodes"]
    end

    test "success with filter by databaseId", %{conn: conn} do
      insert(:prm, :legal_entity)
      legal_entity = insert(:prm, :legal_entity)

      query = """
        query GetLegalEntitiesQuery($filter: LegalEntityFilter) {
          legalEntities(first: 10, filter: $filter) {
            nodes {
              databaseId
            }
          }
        }
      """

      variables = %{filter: %{databaseId: legal_entity.id}}

      resp_body =
        conn
        |> post_query(query, variables)
        |> json_response(200)

      refute resp_body["errors"]
      assert [%{"databaseId" => legal_entity.id}] == get_in(resp_body, ~w(data legalEntities nodes))
    end

    test "success with filter by nhsReviewed", %{conn: conn} do
      [%{id: legal_entity_id}, %{id: legal_entity_id2}] = insert_list(2, :prm, :legal_entity, nhs_reviewed: true)
      insert_list(4, :prm, :legal_entity, nhs_reviewed: false)

      query = """
        query GetLegalEntitiesQuery($filter: LegalEntityFilter) {
          legalEntities(first: 10, filter: $filter) {
            nodes {
              databaseId
            }
          }
        }
      """

      variables = %{filter: %{nhsReviewed: true}}

      resp_body =
        conn
        |> post_query(query, variables)
        |> json_response(200)

      result_ids = get_in(resp_body, ["data", "legalEntities", "nodes", Access.all(), "databaseId"])

      refute resp_body["errors"]
      assert 2 == length(result_ids)
      assert legal_entity_id in result_ids
      assert legal_entity_id2 in result_ids
    end

    test "success with filter by type", %{conn: conn} do
      insert_list(2, :prm, :legal_entity, type: @msp)
      insert_list(4, :prm, :legal_entity, type: @nhs)

      query = """
        query GetLegalEntitiesQuery($filter: LegalEntityFilter) {
          legalEntities(first: 10, filter: $filter) {
            nodes {
              databaseId
              type
            }
          }
        }
      """

      variables = %{filter: %{type: @msp}}

      resp_body =
        conn
        |> post_query(query, variables)
        |> json_response(200)

      resp_entities = get_in(resp_body, ~w(data legalEntities nodes))

      refute resp_body["errors"]
      assert 2 == length(resp_entities)
      assert Enum.all?(resp_entities, &(&1["type"] == @msp))
    end

    test "success with ordering", %{conn: conn} do
      for edrpou <- ["1234567890", "0987654321"], do: insert(:prm, :legal_entity, edrpou: edrpou)

      query = """
        query ListLegalEntitiesQuery($first: Int!, $order_by: LegalEntityFilter!) {
          legalEntities(first: $first, orderBy: $order_by) {
            nodes {
              id
              edrpou
            }
          }
        }
      """

      variables = %{first: 10, order_by: "EDRPOU_ASC"}

      resp_body =
        conn
        |> post_query(query, variables)
        |> json_response(200)

      resp_entities = get_in(resp_body, ~w(data legalEntities nodes))

      refute resp_body["errors"]
      assert "0987654321" == hd(resp_entities)["edrpou"]
    end

    test "success with ordering by nhs_reviewed", %{conn: conn} do
      insert_list(1, :prm, :legal_entity, nhs_reviewed: false)
      insert_list(2, :prm, :legal_entity, nhs_reviewed: true)
      insert_list(4, :prm, :legal_entity, nhs_reviewed: false)

      query = """
          query ListLegalEntitiesQuery($first: Int!, $order_by: LegalEntityFilter!) {
            legalEntities(first: $first, orderBy: $order_by) {
              nodes {
                id
                nhsReviewed
              }
            }
          }
      """

      variables = %{first: 10, order_by: "NHS_REVIEWED_ASC"}

      resp_body =
        conn
        |> post_query(query, variables)
        |> json_response(200)

      resp_entities = get_in(resp_body, ~w(data legalEntities nodes))

      refute resp_body["errors"]

      assert resp_entities
             |> Enum.take(5)
             |> Enum.all?(&(&1["nhsReviewed"] == false))
    end

    test "cursor pagination", %{conn: conn} do
      insert(:prm, :legal_entity)
      insert(:prm, :legal_entity)
      insert(:prm, :legal_entity)

      query = """
        query ListLegalEntitiesQuery($first: Int!) {
          legalEntities(first: $first) {
            pageInfo {
              startCursor
              endCursor
              hasPreviousPage
              hasNextPage
            }
            nodes {
              id
              publicName
              addresses {
                type
                country
              }
            }
          }
        }
      """

      variables = %{first: 2}

      data =
        conn
        |> post_query(query, variables)
        |> json_response(200)
        |> get_in(~w(data legalEntities))

      assert 2 == length(data["nodes"])
      assert data["pageInfo"]["hasNextPage"]
      refute data["pageInfo"]["hasPreviousPage"]

      query = """
        query ListLegalEntitiesQuery($first: Int!, $after: String!) {
          legalEntities(first: $first, after: $after) {
            pageInfo {
              hasPreviousPage
              hasNextPage
            }
            nodes {
              id
              publicName
            }
          }
        }
      """

      variables = %{first: 2, after: data["pageInfo"]["endCursor"]}

      data =
        conn
        |> post_query(query, variables)
        |> json_response(200)
        |> get_in(~w(data legalEntities))

      assert 1 == length(data["nodes"])
      refute data["pageInfo"]["hasNextPage"]
      assert data["pageInfo"]["hasPreviousPage"]
    end

    test "first param not set", %{conn: conn} do
      legal_entity = insert(:prm, :legal_entity)

      query = """
        query ListLegalEntitiesQuery {
          legalEntities(first: 1) {
            nodes {
              databaseId
              divisions {
                nodes {
                  databaseId
                }
              }
            }
          }
        }
      """

      data =
        conn
        |> post_query(query)
        |> json_response(200)

      assert legal_entity.id == hd(get_in(data, ~w(data legalEntities nodes)))["databaseId"]
      assert Enum.any?(data["errors"], &match?(%{"message" => "You must either supply `:first` or `:last`"}, &1))
    end

    test "success with medical_service_provider", %{conn: conn} do
      insert_list(10, :prm, :legal_entity)

      resp_body =
        conn
        |> post_query(@list_legal_entities_msp_query)
        |> json_response(200)

      resp_entities = get_in(resp_body, ~w(data legalEntities nodes))

      assert Enum.all?(resp_entities, &(get_in(&1, ~w(accreditation category)) != nil))
    end

    test "success without medical_service_provider", %{conn: conn} do
      insert_list(10, :prm, :legal_entity, medical_service_provider: nil)

      resp_body =
        conn
        |> post_query(@list_legal_entities_msp_query)
        |> json_response(200)

      resp_entities = get_in(resp_body, ~w(data legalEntities nodes))

      assert Enum.all?(resp_entities, &(&1["medicalServiceProvider"] == nil))
    end
  end

  describe "get by id" do
    test "success", %{conn: conn} do
      insert(:prm, :legal_entity)
      phone = %{"type" => "MOBILE", "number" => "+380201112233"}
      legal_entity = insert(:prm, :legal_entity, phones: [phone])
      division = insert(:prm, :division, legal_entity: legal_entity, name: "Захід Сонця")
      insert(:prm, :division, legal_entity: legal_entity)

      inactive_attrs = [division: division, legal_entity_id: legal_entity.id, employee_type: @owner, is_active: false]
      insert(:prm, :employee, inactive_attrs)
      owner = insert(:prm, :employee, division: division, legal_entity_id: legal_entity.id, employee_type: @owner)
      doctor = insert(:prm, :employee, division: division, legal_entity_id: legal_entity.id, employee_type: @doctor)

      insert(:prm, :related_legal_entity, merged_to: legal_entity, is_active: false)
      related_merged_from = insert(:prm, :related_legal_entity, merged_to: legal_entity)
      insert(:prm, :related_legal_entity, merged_to: legal_entity)
      related_merged_to = insert(:prm, :related_legal_entity, merged_from: legal_entity)

      id = Node.to_global_id("LegalEntity", legal_entity.id)

      query = """
        query GetLegalEntityQuery($id: ID) {
          legalEntity(id: $id) {
            accreditation{
              category
              order_no
              order_date
              issued_date
              expiry_date
            }
            id
            publicName
            nhsVerified
            phones {
              type
              number
            }
            addresses {
              type
              country
            }
            archive {
              date
              place
            }
            license {
              license_number
              issued_by
              issued_date
              active_from_date
              order_no
              expiry_date
              what_licensed
            }
            receiverFundsCode
            owner {
              databaseId
              position
              additionalInfo{
                specialities{
                  speciality
                  speciality_officio
                }
              }
              party {
                databaseId
                firstName
              }
              legal_entity {
                databaseId
                publicName
              }
            }
            employees(first: 2, filter: {isActive: true}){
              nodes {
                databaseId
                additionalInfo{
                  specialities{
                    speciality
                    speciality_officio
                  }
                }
                party {
                  databaseId
                  firstName
                }
                legal_entity {
                  databaseId
                  publicName
                }
              }
            }
            divisions(first: 1){
              nodes {
                databaseId
                name
                email
                addresses {
                  area
                  region
                }
              }
            }
            mergedFromLegalEntities(first: 1, filter: {isActive: true}){
              nodes {
                databaseId
                mergedToLegalEntity {
                  databaseId
                  publicName
                }
                mergedFromLegalEntity {
                  databaseId
                  publicName
                }
              }
            }
            mergedToLegalEntity {
              databaseId
              mergedToLegalEntity {
                databaseId
                publicName
              }
            }
          }
        }
      """

      variables = %{id: id}

      resp =
        conn
        |> post_query(query, variables)
        |> json_response(200)
        |> get_in(~w(data legalEntity))

      assert legal_entity.public_name == resp["publicName"]
      assert legal_entity.phones == resp["phones"]
      assert legal_entity.archive == resp["archive"]
      assert Map.has_key?(resp, "license")
      assert "some" == get_in(resp, ~w(accreditation category))

      # mergedToLegalEntity
      assert related_merged_to.id == resp["mergedToLegalEntity"]["databaseId"]

      # mergedFromLegalEntity
      assert related_merged_from.id == hd(resp["mergedFromLegalEntities"]["nodes"])["databaseId"]

      # owner
      assert owner.id == resp["owner"]["databaseId"]

      # employees
      employees_from_resp = resp["employees"]["nodes"]
      assert 2 = length(employees_from_resp)

      Enum.each(employees_from_resp, fn employee_from_resp ->
        assert employee_from_resp["databaseId"] in [doctor.id, owner.id]
        assert Map.has_key?(employee_from_resp, "additionalInfo")
        assert Map.has_key?(employee_from_resp, "legal_entity")
        assert Map.has_key?(employee_from_resp["additionalInfo"], "specialities")

        assert [
                 %{
                   "speciality" => "PEDIATRICIAN",
                   "speciality_officio" => true
                 }
               ] == employee_from_resp["additionalInfo"]["specialities"]
      end)

      # msp
      assert legal_entity.accreditation |> Jason.encode!() |> Jason.decode!() == resp["accreditation"]

      assert legal_entity.license |> Map.take(~w(
        license_number
        issued_by
        issued_date
        active_from_date
        order_no
        expiry_date
        what_licensed
      )a) |> Jason.encode!() |> Jason.decode!() == resp["license"]

      # divisions
      assert 1 == length(resp["divisions"]["nodes"])
      division_from_resp = hd(resp["divisions"]["nodes"])
      assert division.id == division_from_resp["databaseId"]
      assert match?(%{"area" => _, "region" => _}, hd(division_from_resp["addresses"]))
    end

    test "divisions with cursor pagination", %{conn: conn} do
      legal_entity = insert(:prm, :legal_entity)
      insert_list(10, :prm, :division, legal_entity: legal_entity)

      id = Node.to_global_id("LegalEntity", legal_entity.id)

      # get first 2 divisions

      query = """
        query GetLegalEntityQuery($id: ID) {
          legalEntity(id: $id) {
            databaseId
            divisions(first: 2){
              pageInfo {
                startCursor
                endCursor
              }
              nodes {
                databaseId
              }
            }
          }
        }
      """

      variables = %{id: id}

      resp =
        conn
        |> post_query(query, variables)
        |> json_response(200)

      refute resp["errors"]

      end_cursor = get_in(resp, ~w(data legalEntity divisions pageInfo endCursor))

      # get next 2 divisions

      query = """
        query GetLegalEntityQuery($id: ID, $after: String) {
          legalEntity(id: $id) {
            databaseId
            divisions(first: 2, after: $after){
              pageInfo {
                startCursor
                endCursor
              }
              nodes {
                databaseId
              }
            }
          }
        }
      """

      variables = %{id: id, after: end_cursor}

      resp =
        conn
        |> post_query(query, variables)
        |> json_response(200)

      refute resp["errors"]
      start_cursor = get_in(resp, ~w(data legalEntity divisions pageInfo startCursor))

      # get previous 2 divisions

      query = """
        query GetLegalEntityQuery($id: ID, $before: String) {
          legalEntity(id: $id) {
            databaseId
            divisions(last: 10, before: $before){
              pageInfo {
                startCursor
                endCursor
              }
              nodes {
                databaseId
              }
            }
          }
        }
      """

      variables = %{id: id, before: start_cursor}

      resp =
        conn
        |> post_query(query, variables)
        |> json_response(200)

      refute resp["errors"]
    end

    test "get owner", %{conn: conn} do
      legal_entity = insert(:prm, :legal_entity)
      insert(:prm, :employee, legal_entity_id: legal_entity.id, employee_type: @owner, is_active: false)
      owner = insert(:prm, :employee, legal_entity_id: legal_entity.id, employee_type: @owner, is_active: false)

      query = """
        query GetLegalEntityQuery($id: ID) {
          legalEntity(id: $id) {
            owner {
              databaseId
            }
          }
        }
      """

      id = Node.to_global_id("LegalEntity", legal_entity.id)
      variables = %{id: id}

      resp =
        conn
        |> post_query(query, variables)
        |> json_response(200)

      refute resp["errors"]
      assert owner.id == get_in(resp, ~w(data legalEntity owner databaseId))
    end
  end

  describe "nsh verify legal_entity" do
    setup %{conn: conn} do
      %{conn: put_scope(conn, "legal_entity:nhs_verify")}
    end

    test "success", %{conn: conn} do
      %{id: id} = insert(:prm, :legal_entity, nhs_verified: true)

      variables = %{input: %{id: Node.to_global_id("LegalEntity", id), nhs_verified: false}}

      resp_body =
        conn
        |> put_client_id(id)
        |> post_query(@nhs_verify_query, variables)
        |> json_response(200)

      resp_entity = get_in(resp_body, ~w(data nhsVerifyLegalEntity legalEntity))

      assert %{"nhsVerified" => false, "databaseId" => ^id} = resp_entity
    end

    test "legal_entity already verified", %{conn: conn} do
      %{id: id} = insert(:prm, :legal_entity, nhs_verified: true)
      variables = %{input: %{id: Node.to_global_id("LegalEntity", id), nhs_verified: true}}

      resp_body =
        conn
        |> put_client_id(id)
        |> post_query(@nhs_verify_query, variables)
        |> json_response(200)

      assert %{"errors" => [error], "data" => %{"nhsVerifyLegalEntity" => nil}} = resp_body
      assert %{"extensions" => %{"code" => "CONFLICT"}, "message" => _} = error
    end

    test "legal_entity is not active", %{conn: conn} do
      %{id: id} = insert(:prm, :legal_entity, status: @legal_entity_status_closed)
      variables = %{input: %{id: Node.to_global_id("LegalEntity", id), nhs_verified: true}}

      resp_body =
        conn
        |> put_client_id(id)
        |> post_query(@nhs_verify_query, variables)
        |> json_response(200)

      resp_entity = get_in(resp_body, ~w(data nhsVerifyLegalEntity legalEntity))
      %{"errors" => [error]} = resp_body

      refute resp_entity
      assert "CONFLICT" == error["extensions"]["code"]
    end

    test "not found", %{conn: conn} do
      variables = %{input: %{id: Node.to_global_id("LegalEntity", Ecto.UUID.generate()), nhs_verified: true}}

      resp_body =
        conn
        |> put_client_id()
        |> post_query(@nhs_verify_query, variables)
        |> json_response(200)

      assert %{"errors" => [error], "data" => %{"nhsVerifyLegalEntity" => nil}} = resp_body
      assert %{"extensions" => %{"code" => "NOT_FOUND"}, "message" => _} = error
    end

    test "fails on unreviewed legal_entity by nhs", %{conn: conn} do
      %{id: id} = insert(:prm, :legal_entity, nhs_reviewed: false)
      variables = %{input: %{id: Node.to_global_id("LegalEntity", id), nhs_verified: true}}

      resp_body =
        conn
        |> put_client_id(id)
        |> post_query(@nhs_verify_query, variables)
        |> json_response(200)

      resp_entity = get_in(resp_body, ~w(data nhsVerifyLegalEntity legalEntity))

      assert [error] = resp_body["errors"]
      assert "CONFLICT" == error["extensions"]["code"]
      refute resp_entity
    end
  end

  describe "legal_entity nhs review" do
    setup %{conn: conn} do
      %{
        conn:
          conn
          |> put_scope("legal_entity:nhs_verify")
          |> put_consumer_id()
      }
    end

    test "success", %{conn: conn} do
      %{id: id} = insert(:prm, :legal_entity, nhs_reviewed: false)

      variables = %{input: %{id: Node.to_global_id("LegalEntity", id)}}

      resp_body =
        conn
        |> put_client_id(id)
        |> post_query(@nhs_review_query, variables)
        |> json_response(200)

      resp_entity = get_in(resp_body, ~w(data nhsReviewLegalEntity legalEntity))
      legal_entity = PRMRepo.get(LegalEntity, id)

      refute resp_body["errors"]
      assert %{"databaseId" => ^id, "nhsReviewed" => true} = resp_entity
      assert %{id: ^id, nhs_reviewed: true} = legal_entity
    end

    test "fails: legal_entity already reviewed", %{conn: conn} do
      %{id: id} = insert(:prm, :legal_entity, nhs_reviewed: true)
      variables = %{input: %{id: Node.to_global_id("LegalEntity", id)}}

      resp_body =
        conn
        |> put_client_id(id)
        |> post_query(@nhs_review_query, variables)
        |> json_response(200)

      resp_entity = get_in(resp_body, ~w(data nhsReviewLegalEntity legalEntity))

      refute resp_entity
      assert "CONFLICT" == hd(resp_body["errors"])["extensions"]["code"]
    end

    test "fails: legal_entity is not active", %{conn: conn} do
      %{id: id} = insert(:prm, :legal_entity, status: LegalEntity.status(:closed))
      variables = %{input: %{id: Node.to_global_id("LegalEntity", id)}}

      resp_body =
        conn
        |> put_client_id(id)
        |> post_query(@nhs_review_query, variables)
        |> json_response(200)

      resp_entity = get_in(resp_body, ~w(data nhsReviewLegalEntity legalEntity))

      refute resp_entity
      assert "CONFLICT" == hd(resp_body["errors"])["extensions"]["code"]
    end

    test "not found", %{conn: conn} do
      variables = %{input: %{id: Node.to_global_id("LegalEntity", UUID.generate())}}

      resp_body =
        conn
        |> put_client_id(UUID.generate())
        |> post_query(@nhs_review_query, variables)
        |> json_response(200)

      resp_entity = get_in(resp_body, ~w(data nhsReviewLegalEntity legalEntity))

      refute resp_entity
      assert [error] = resp_body["errors"]
      assert "NOT_FOUND" == error["extensions"]["code"]
    end
  end

  describe "nhs comment" do
    test "success", %{conn: conn} do
      %{id: id} = insert(:prm, :legal_entity)

      nhs_comment = "test comment here"

      variables = %{
        input: %{
          id: Node.to_global_id("LegalEntity", id),
          nhs_comment: nhs_comment
        }
      }

      resp_body =
        conn
        |> put_scope("legal_entity:nhs_verify")
        |> put_consumer_id()
        |> put_client_id(id)
        |> post_query(@nhs_comment_query, variables)
        |> json_response(200)

      resp_entity = get_in(resp_body, ~w(data nhsCommentLegalEntity legalEntity))
      legal_entity = PRMRepo.get(LegalEntity, id)

      refute resp_body["errors"]
      assert %{"databaseId" => ^id, "nhsComment" => ^nhs_comment} = resp_entity
      assert %{id: ^id, nhs_comment: ^nhs_comment} = legal_entity
    end

    test "fails due to legal entity hasn't beed reviewed by nhs", %{conn: conn} do
      %{id: id} = insert(:prm, :legal_entity, nhs_reviewed: false)

      variables = %{
        input: %{
          id: Node.to_global_id("LegalEntity", id),
          nhs_comment: ""
        }
      }

      resp_body =
        conn
        |> put_scope("legal_entity:nhs_verify")
        |> put_consumer_id()
        |> put_client_id(id)
        |> post_query(@nhs_comment_query, variables)
        |> json_response(200)

      resp_entity = get_in(resp_body, ~w(data nhsCommentLegalEntity legalEntity))

      refute resp_entity
      assert [error] = resp_body["errors"]
      assert "CONFLICT" == error["extensions"]["code"]
    end
  end
end
