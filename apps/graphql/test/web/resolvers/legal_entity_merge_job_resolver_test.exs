defmodule GraphQLWeb.LegalEntityMergeJobResolverTest do
  @moduledoc false

  use GraphQLWeb.ConnCase, async: true

  import Core.Factories
  import Mox

  alias Absinthe.Relay.Node
  alias BSON.ObjectId
  alias Core.LegalEntities.LegalEntity
  alias Ecto.UUID
  alias TasKafka.Jobs

  setup :verify_on_exit!

  @tax_id "002233445566"

  @query """
    mutation MergeLegalEntitiesMutation($input: MergeLegalEntitiesInput!) {
      mergeLegalEntities(input: $input) {
        legalEntityMergeJob {
          id
          status
        }
      }
    }
  """

  setup %{conn: conn} do
    consumer_id = UUID.generate()

    party = insert(:prm, :party, tax_id: @tax_id)
    insert(:prm, :party_user, party: party, user_id: consumer_id)

    conn =
      conn
      |> put_scope("legal_entity:merge")
      |> put_drfo(@tax_id)
      |> put_consumer_id(consumer_id)

    {:ok, %{conn: conn}}
  end

  describe "merge legal entities" do
    test "success", %{conn: conn} do
      expect_decode_and_validate()

      from = insert(:prm, :legal_entity)
      to = insert(:prm, :legal_entity)

      signed_content = merged_signed_content(from, to)

      job =
        conn
        |> post_query(@query, input_signed_content(signed_content))
        |> json_response(200)
        |> get_in(~w(data mergeLegalEntities legalEntityMergeJob))

      assert "PENDING" == job["status"]
    end

    test "invalid scope", %{conn: conn} do
      resp =
        conn
        |> put_scope("scope:not-allowed")
        |> post_query(@query, input_signed_content(""))
        |> json_response(200)

      assert match?(%{"mergeLegalEntities" => nil}, resp["data"])
      assert Enum.any?(resp["errors"], &match?(%{"extensions" => %{"code" => "FORBIDDEN"}}, &1))
    end

    test "merged from legal entity with status CLOSED", %{conn: conn} do
      expect_decode_and_validate()

      from = insert(:prm, :legal_entity, status: LegalEntity.status(:closed))
      to = insert(:prm, :legal_entity)

      signed_content = merged_signed_content(from, to)

      resp =
        conn
        |> post_query(@query, input_signed_content(signed_content))
        |> json_response(200)

      assert match?(%{"mergeLegalEntities" => nil}, resp["data"])
      assert Enum.any?(resp["errors"], &match?(%{"message" => "Merged from legal entity must be active"}, &1))
    end

    test "merged to legal entity with status CLOSED", %{conn: conn} do
      expect_decode_and_validate()

      from = insert(:prm, :legal_entity)
      to = insert(:prm, :legal_entity, status: LegalEntity.status(:closed))

      signed_content = merged_signed_content(from, to)

      resp =
        conn
        |> post_query(@query, input_signed_content(signed_content))
        |> json_response(200)

      assert match?(%{"mergeLegalEntities" => nil}, resp["data"])
      assert Enum.any?(resp["errors"], &match?(%{"message" => "Merged to legal entity must be active"}, &1))
    end

    test "merge with invalid legal entity type", %{conn: conn} do
      expect_decode_and_validate(2)

      from = insert(:prm, :legal_entity)
      to1 = insert(:prm, :legal_entity, type: LegalEntity.type(:mis))
      to2 = insert(:prm, :legal_entity, type: LegalEntity.type(:pharmacy))

      Enum.each([to1, to2], fn to ->
        resp =
          conn
          |> post_query(@query, input_signed_content(merged_signed_content(from, to)))
          |> json_response(200)

        assert match?(%{"mergeLegalEntities" => nil}, resp["data"])
        assert Enum.any?(resp["errors"], &match?(%{"message" => "Invalid legal entity type"}, &1))
      end)
    end

    test "merged to already merged", %{conn: conn} do
      expect_decode_and_validate()

      from = insert(:prm, :legal_entity)
      to = insert(:prm, :legal_entity)
      insert(:prm, :related_legal_entity, merged_from: to)

      signed_content = merged_signed_content(from, to)

      resp =
        conn
        |> post_query(@query, input_signed_content(signed_content))
        |> json_response(200)

      assert match?(%{"mergeLegalEntities" => nil}, resp["data"])

      assert Enum.any?(
               resp["errors"],
               &match?(%{"message" => "Merged to legal entity is in the process of reorganization itself"}, &1)
             )
    end

    test "merged from already merged", %{conn: conn} do
      expect_decode_and_validate()

      from = insert(:prm, :legal_entity)
      to = insert(:prm, :legal_entity)
      insert(:prm, :related_legal_entity, merged_from: from)

      signed_content = merged_signed_content(from, to)

      resp =
        conn
        |> post_query(@query, input_signed_content(signed_content))
        |> json_response(200)

      assert match?(%{"mergeLegalEntities" => nil}, resp["data"])

      assert Enum.any?(
               resp["errors"],
               &match?(%{"message" => "Merged from legal entity is already in the process of reorganization"}, &1)
             )
    end
  end

  describe "get by id" do
    setup %{conn: conn} do
      {:ok, %{conn: put_scope(conn, "legal_entity_merge_job:read")}}
    end

    test "success", %{conn: conn} do
      merged_to = insert(:prm, :legal_entity)
      merged_from = insert(:prm, :legal_entity)

      meta = %{
        "merged_to_legal_entity" => %{
          "id" => merged_to.id,
          "name" => merged_to.name,
          "edrpou" => merged_to.edrpou
        },
        "merged_from_legal_entity" => %{
          "id" => merged_from.id,
          "name" => merged_from.name,
          "edrpou" => merged_from.edrpou
        }
      }

      {:ok, job_id, _} = create_job(meta)
      Jobs.processed(job_id, %{related_legal_entity_id: UUID.generate()})
      id = Node.to_global_id("LegalEntityMergeJob", job_id)

      query = """
        query GetLegalEntityMergeJobQuery($id: ID) {
          legalEntityMergeJob(id: $id) {
            id
            status
            startedAt
            endedAt
            mergedToLegalEntity{
              id
              name
              edrpou
            }
            mergedFromLegalEntity{
              id
              name
              edrpou
            }
          }
        }
      """

      variables = %{id: id}

      resp =
        conn
        |> post_query(query, variables)
        |> json_response(200)
        |> get_in(~w(data legalEntityMergeJob))

      assert meta["merged_to_legal_entity"] == resp["mergedToLegalEntity"]
      assert meta["merged_from_legal_entity"] == resp["mergedFromLegalEntity"]
      assert "PROCESSED" == resp["status"]
    end
  end

  defp create_job(meta) do
    {:ok, job} = Jobs.create(meta)
    {:ok, ObjectId.encode!(job._id), job}
  end

  defp merged_signed_content(merged_from, merged_to) do
    %{
      "merged_from_legal_entity" => %{
        "id" => merged_from.id,
        "name" => merged_from.name,
        "edrpou" => merged_from.edrpou
      },
      "merged_to_legal_entity" => %{
        "id" => merged_to.id,
        "name" => merged_to.name,
        "edrpou" => merged_to.edrpou
      },
      "reason" => "Because I can"
    }
    |> Jason.encode!()
    |> Base.encode64()
  end

  defp expect_decode_and_validate(n \\ 1) do
    expect(SignatureMock, :decode_and_validate, n, fn signed_content, :base64, _headers ->
      content = signed_content |> Base.decode64!() |> Jason.decode!()

      data = %{
        "content" => content,
        "signatures" => [
          %{
            "is_valid" => true,
            "signer" => %{
              "drfo" => @tax_id,
              "surname" => content["last_name"],
              "given_name" => "Сара Коннор"
            },
            "validation_error_message" => ""
          }
        ]
      }

      {:ok, %{"data" => data}}
    end)
  end

  defp input_signed_content(content) do
    %{
      input: %{
        signedContent: %{
          content: content,
          encoding: "BASE64"
        }
      }
    }
  end
end
