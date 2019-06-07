defmodule EHealth.Web.ContractRequest.CapitationControllerTest do
  @moduledoc false

  use EHealth.Web.ConnCase

  import Core.Expectations.Man
  import Core.Expectations.Signature
  import Mox

  alias Core.ContractRequests.CapitationContractRequest
  alias Core.Contracts.CapitationContract
  alias Core.Divisions.Division
  alias Core.Employees.Employee
  alias Core.LegalEntities.LegalEntity
  alias Core.Utils.NumberGenerator
  alias Ecto.UUID

  @capitation "capitation"
  @contract_request_status_new CapitationContractRequest.status(:new)
  @contract_request_status_in_process CapitationContractRequest.status(:in_process)
  @contract_request_status_declined CapitationContractRequest.status(:declined)
  @contract_status_verified CapitationContract.status(:verified)

  @forbidden_statuses_for_termination [
    CapitationContractRequest.status(:declined),
    CapitationContractRequest.status(:signed),
    CapitationContractRequest.status(:terminated)
  ]

  @allowed_statuses_for_termination [
    CapitationContractRequest.status(:new),
    CapitationContractRequest.status(:approved),
    CapitationContractRequest.status(:pending_nhs_sign),
    CapitationContractRequest.status(:nhs_signed)
  ]

  describe "capitation contract request draft" do
    test "success create draft", %{conn: conn} do
      msp()

      expect(MediaStorageMock, :create_signed_url, 4, fn _, _, resource, _ ->
        {:ok, %{secret_url: "http://some_url/#{resource}"}}
      end)

      resp =
        conn
        |> put_client_id_header(UUID.generate())
        |> post(contract_request_path(conn, :draft, @capitation))
        |> json_response(200)

      assert Enum.all?(
               ~w(id statute_url additional_document_url),
               &Map.has_key?(resp["data"], &1)
             )

      # query path without contract type
      conn
      |> put_client_id_header(UUID.generate())
      |> post("/api/contract_requests")
      |> json_response(200)
    end
  end

  describe "create capitation contract request" do
    test "employee division is not active", %{conn: conn} do
      msp()
      %{legal_entity: legal_entity, employee: employee, party_user: party_user} = prepare_data()
      division = insert(:prm, :division)

      expect(MediaStorageMock, :create_signed_url, 2, fn "HEAD", _, resource, _ ->
        {:ok, %{secret_url: "http://some_url/#{resource}"}}
      end)

      expect(MediaStorageMock, :verify_uploaded_file, 2, fn _, resource ->
        {:ok, %HTTPoison.Response{status_code: 200, headers: [{"ETag", Jason.encode!(resource)}]}}
      end)

      params =
        division
        |> prepare_capitation_params(employee)
        |> Map.put("contractor_divisions", [division.id, UUID.generate()])

      expect_signed_content(params, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: party_user.party.last_name
      })

      signed_content = params |> Jason.encode!() |> Base.encode64()

      resp =
        conn
        |> put_client_id_header(legal_entity.id)
        |> put_consumer_id_header(party_user.user_id)
        |> put_req_header("drfo", legal_entity.edrpou)
        |> post(contract_request_path(conn, :create, @capitation, UUID.generate()), %{
          "signed_content" => signed_content,
          "signed_content_encoding" => "base64"
        })
        |> json_response(422)

      assert %{
               "invalid" => [
                 %{
                   "entry" => "$.contractor_divisions.[0]",
                   "rules" => [
                     %{
                       "description" => "Division must be active and within current legal_entity",
                       "params" => [],
                       "rule" => "invalid"
                     }
                   ]
                 },
                 %{
                   "entry" => "$.contractor_divisions.[1]",
                   "rules" => [
                     %{
                       "description" => "Division not found",
                       "params" => [],
                       "rule" => "invalid"
                     }
                   ]
                 }
               ]
             } = resp["error"]
    end

    test "edrpou in sign and in legal entity mismatch", %{conn: conn} do
      msp()
      %{legal_entity: legal_entity, employee: employee, party_user: party_user} = prepare_data()
      division = insert(:prm, :division)

      expect(MediaStorageMock, :create_signed_url, 2, fn "HEAD", _, resource, _ ->
        {:ok, %{secret_url: "http://some_url/#{resource}"}}
      end)

      expect(MediaStorageMock, :verify_uploaded_file, 2, fn _, resource ->
        {:ok, %HTTPoison.Response{status_code: 200, headers: [{"ETag", Jason.encode!(resource)}]}}
      end)

      conn =
        conn
        |> put_client_id_header(legal_entity.id)
        |> put_consumer_id_header(party_user.user_id)

      params =
        prepare_capitation_params(division, employee)
        |> Map.put("contractor_divisions", [division.id, UUID.generate()])

      drfo_signed_content(params, party_user.party.tax_id, party_user.party.last_name)

      conn =
        post(conn, contract_request_path(conn, :create, @capitation, UUID.generate()), %{
          "signed_content" => params |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })

      resp = json_response(conn, 422)

      assert %{
               "invalid" => [%{"entry" => "$.drfo"}],
               "type" => "validation_failed"
             } = resp["error"]
    end

    test "last name of party and surname of sign and in legal entity mismatch", %{conn: conn} do
      msp()
      %{legal_entity: legal_entity, employee: employee, party_user: party_user} = prepare_data()
      division = insert(:prm, :division)

      expect(MediaStorageMock, :create_signed_url, 2, fn "HEAD", _, resource, _ ->
        {:ok, %{secret_url: "http://some_url/#{resource}"}}
      end)

      expect(MediaStorageMock, :verify_uploaded_file, 2, fn _, resource ->
        {:ok, %HTTPoison.Response{status_code: 200, headers: [{"ETag", Jason.encode!(resource)}]}}
      end)

      conn =
        conn
        |> put_client_id_header(legal_entity.id)
        |> put_consumer_id_header(party_user.user_id)

      params =
        prepare_capitation_params(division, employee)
        |> Map.put("contractor_divisions", [division.id, UUID.generate()])

      expect_signed_content(params, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: "Інше прізвище"
      })

      resp =
        conn
        |> post(contract_request_path(conn, :create, @capitation, UUID.generate()), %{
          "signed_content" => params |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(422)

      assert %{
               "invalid" => [
                 %{
                   "entry" => "$.last_name",
                   "rules" => [
                     %{
                       "description" => "Signer surname does not match with current user last_name"
                     }
                   ]
                 }
               ],
               "type" => "validation_failed"
             } = resp["error"]
    end

    test "surname of sign does not exists", %{conn: conn} do
      msp()
      %{legal_entity: legal_entity, employee: employee, party_user: party_user} = prepare_data()
      division = insert(:prm, :division)

      expect(MediaStorageMock, :create_signed_url, 2, fn "HEAD", _, resource, _ ->
        {:ok, %{secret_url: "http://some_url/#{resource}"}}
      end)

      expect(MediaStorageMock, :verify_uploaded_file, 2, fn _, resource ->
        {:ok, %HTTPoison.Response{status_code: 200, headers: [{"ETag", Jason.encode!(resource)}]}}
      end)

      conn =
        conn
        |> put_client_id_header(legal_entity.id)
        |> put_consumer_id_header(party_user.user_id)

      params =
        prepare_capitation_params(division, employee)
        |> Map.put("contractor_divisions", [division.id, UUID.generate()])

      expect_signed_content(params, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: nil
      })

      resp =
        conn
        |> post(contract_request_path(conn, :create, @capitation, UUID.generate()), %{
          "signed_content" => params |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(422)

      assert %{
               "invalid" => [
                 %{
                   "entry" => "$.surname",
                   "rules" => [
                     %{
                       "description" => "Signer surname is not exist in sign info"
                     }
                   ]
                 }
               ],
               "type" => "validation_failed"
             } = resp["error"]
    end

    test "party for user_id not found", %{conn: conn} do
      msp()
      %{legal_entity: legal_entity, employee: employee} = prepare_data()
      division = insert(:prm, :division)

      expect(MediaStorageMock, :create_signed_url, 2, fn "HEAD", _, resource, _ ->
        {:ok, %{secret_url: "http://some_url/#{resource}"}}
      end)

      expect(MediaStorageMock, :verify_uploaded_file, 2, fn _, resource ->
        {:ok, %HTTPoison.Response{status_code: 200, headers: [{"ETag", Jason.encode!(resource)}]}}
      end)

      conn =
        conn
        |> put_client_id_header(legal_entity.id)
        |> put_consumer_id_header(UUID.generate())

      params =
        prepare_capitation_params(division, employee)
        |> Map.put("contractor_divisions", [division.id, UUID.generate()])

      drfo_signed_content(params, [%{drfo: "test", surname: "Підпісант"}])

      conn
      |> post(contract_request_path(conn, :create, @capitation, UUID.generate()), %{
        "signed_content" => params |> Jason.encode!() |> Base.encode64(),
        "signed_content_encoding" => "base64"
      })
      |> json_response(403)
    end

    test "invalid user drfo in DS", %{conn: conn} do
      msp()
      %{legal_entity: legal_entity, employee: employee, party_user: party_user} = prepare_data()
      division = insert(:prm, :division)

      expect(MediaStorageMock, :create_signed_url, 2, fn "HEAD", _, resource, _ ->
        {:ok, %{secret_url: "http://some_url/#{resource}"}}
      end)

      expect(MediaStorageMock, :verify_uploaded_file, 2, fn _, resource ->
        {:ok, %HTTPoison.Response{status_code: 200, headers: [{"ETag", Jason.encode!(resource)}]}}
      end)

      conn =
        conn
        |> put_client_id_header(legal_entity.id)
        |> put_consumer_id_header(party_user.user_id)

      params = prepare_capitation_params(division, employee)

      expect_signed_content(params, %{
        edrpou: legal_entity.edrpou,
        drfo: "test",
        surname: party_user.party.last_name
      })

      resp =
        conn
        |> post(contract_request_path(conn, :create, @capitation, UUID.generate()), %{
          "signed_content" => params |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(422)

      assert %{
               "invalid" => [
                 %{"entry_type" => "request", "rules" => [%{"rule" => "json"}]}
               ],
               "message" => "Does not match the signer drfo",
               "type" => "request_malformed"
             } = resp["error"]
    end

    test "external contractor division is not present in contract divisions", %{conn: conn} do
      msp()

      %{
        legal_entity: legal_entity,
        division: division,
        employee: employee,
        party_user: party_user
      } = prepare_data()

      expect(MediaStorageMock, :create_signed_url, 2, fn "HEAD", _, resource, _ ->
        {:ok, %{secret_url: "http://some_url/#{resource}"}}
      end)

      expect(MediaStorageMock, :verify_uploaded_file, 2, fn _, resource ->
        {:ok, %HTTPoison.Response{status_code: 200, headers: [{"ETag", Jason.encode!(resource)}]}}
      end)

      conn =
        conn
        |> put_client_id_header(legal_entity.id)
        |> put_consumer_id_header(party_user.user_id)
        |> put_req_header("drfo", legal_entity.edrpou)

      %{id: external_legal_entity_id} = insert(:prm, :legal_entity)

      params =
        division
        |> prepare_capitation_params(employee)
        |> Map.delete("external_contractor_flag")
        |> Map.put("external_contractors", [
          %{
            "divisions" => [%{"id" => UUID.generate(), "medical_service" => "Послуга ПМД"}],
            "legal_entity_id" => external_legal_entity_id,
            "contract" => %{
              "number" => "1234567",
              "issued_at" => Date.to_iso8601(Date.utc_today()),
              "expires_at" => Date.to_iso8601(Date.utc_today())
            }
          }
        ])

      expect_signed_content(params, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: party_user.party.last_name
      })

      resp =
        conn
        |> post(contract_request_path(conn, :create, @capitation, UUID.generate()), %{
          "signed_content" => params |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(422)

      assert_error(
        resp,
        "$.external_contractors.[0].divisions.[0].id",
        "The division is not belong to contractor_divisions"
      )
    end

    test "external contractors invalid legal entity", %{conn: conn} do
      msp()

      %{
        legal_entity: legal_entity,
        division: division,
        employee: employee,
        user_id: user_id,
        owner: owner,
        party_user: party_user
      } = prepare_data()

      expect(MediaStorageMock, :create_signed_url, 2, fn "HEAD", _, resource, _ ->
        {:ok, %{secret_url: "http://some_url/#{resource}"}}
      end)

      expect(MediaStorageMock, :verify_uploaded_file, 2, fn _, resource ->
        {:ok, %HTTPoison.Response{status_code: 200, headers: [{"ETag", Jason.encode!(resource)}]}}
      end)

      conn =
        conn
        |> put_client_id_header(legal_entity.id)
        |> put_consumer_id_header(user_id)
        |> put_req_header("drfo", legal_entity.edrpou)

      start_date = contract_start_date()
      end_date = Date.add(start_date, 30)
      expires_at = Date.to_iso8601(Date.add(start_date, 1))

      %{id: valid_id} = insert(:prm, :legal_entity)

      contractor =
        division
        |> prepare_capitation_params(employee, expires_at)
        |> Map.get("external_contractors")
        |> Enum.at(0)

      external_contractors = [
        %{contractor | "legal_entity_id" => UUID.generate()},
        %{contractor | "legal_entity_id" => valid_id},
        %{contractor | "legal_entity_id" => UUID.generate()}
      ]

      params =
        division
        |> prepare_capitation_params(employee, expires_at)
        |> Map.put("contractor_owner_id", owner.id)
        |> Map.put("start_date", Date.to_iso8601(start_date))
        |> Map.put("end_date", Date.to_iso8601(end_date))
        |> Map.put("external_contractors", external_contractors)

      expect_signed_content(params, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: party_user.party.last_name
      })

      resp =
        conn
        |> post(contract_request_path(conn, :create, @capitation, UUID.generate()), %{
          "signed_content" => params |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(422)

      assert %{
               "invalid" => [
                 %{
                   "entry" => "$.external_contractors.[0].legal_entity_id",
                   "rules" => [
                     %{
                       "description" => "Active $external_contractors.[0].legal_entity_id does not exist",
                       "params" => [],
                       "rule" => "invalid"
                     }
                   ]
                 },
                 %{
                   "entry" => "$.external_contractors.[2].legal_entity_id",
                   "rules" => [
                     %{
                       "description" => "Active $external_contractors.[2].legal_entity_id does not exist",
                       "params" => [],
                       "rule" => "invalid"
                     }
                   ]
                 }
               ],
               "type" => "validation_failed"
             } = resp["error"]
    end

    test "invalid legal_entity client_type", %{conn: conn} do
      %{
        legal_entity: legal_entity,
        employee: employee,
        division: division,
        user_id: user_id,
        party_user: party_user
      } = prepare_data("OWNER", "PHARMACY")

      expires_at = Date.to_iso8601(Date.add(contract_start_date(), 1))
      params = prepare_capitation_params(division, employee, expires_at)

      expect_signed_content(params, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: party_user.party.last_name
      })

      reason =
        conn
        |> put_client_id_header(legal_entity.id)
        |> put_consumer_id_header(user_id)
        |> put_req_header("drfo", legal_entity.edrpou)
        |> post(contract_request_path(conn, :create, @capitation, UUID.generate()), %{
          "signed_content" => params |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(409)
        |> get_in(~w(error message))

      assert ~s(Contract type "CAPITATION" is not allowed for legal_entity with type "PHARMACY") == reason
    end

    test "invalid expires_at date", %{conn: conn} do
      msp()

      %{
        legal_entity: legal_entity,
        division: division,
        employee: employee,
        party_user: party_user
      } = prepare_data()

      expect(MediaStorageMock, :create_signed_url, 2, fn "HEAD", _, resource, _ ->
        {:ok, %{secret_url: "http://some_url/#{resource}"}}
      end)

      expect(MediaStorageMock, :verify_uploaded_file, 2, fn _, resource ->
        {:ok, %HTTPoison.Response{status_code: 200, headers: [{"ETag", Jason.encode!(resource)}]}}
      end)

      conn =
        conn
        |> put_client_id_header(legal_entity.id)
        |> put_consumer_id_header(party_user.user_id)
        |> put_req_header("drfo", legal_entity.edrpou)

      params =
        division
        |> prepare_capitation_params(employee, "2018-01-01")
        |> Map.put("start_date", "2018-02-01")
        |> Map.delete("external_contractor_flag")

      expect_signed_content(params, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: party_user.party.last_name
      })

      resp =
        conn
        |> post(contract_request_path(conn, :create, @capitation, UUID.generate()), %{
          "signed_content" => params |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(422)

      assert_error(
        resp,
        "$.external_contractors.[0].contract.expires_at",
        "Expires date must be greater than contract start_date"
      )
    end

    test "invalid external_contractor_flag", %{conn: conn} do
      msp()

      %{
        legal_entity: legal_entity,
        division: division,
        employee: employee,
        party_user: party_user
      } = prepare_data()

      expect(MediaStorageMock, :create_signed_url, 2, fn "HEAD", _, resource, _ ->
        {:ok, %{secret_url: "http://some_url/#{resource}"}}
      end)

      expect(MediaStorageMock, :verify_uploaded_file, 2, fn _, resource ->
        {:ok, %HTTPoison.Response{status_code: 200, headers: [{"ETag", Jason.encode!(resource)}]}}
      end)

      conn =
        conn
        |> put_client_id_header(legal_entity.id)
        |> put_consumer_id_header(party_user.user_id)
        |> put_req_header("drfo", legal_entity.edrpou)

      params =
        division
        |> prepare_capitation_params(employee, "2018-03-01")
        |> Map.put("start_date", "2018-02-01")
        |> Map.delete("external_contractor_flag")

      expect_signed_content(params, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: party_user.party.last_name
      })

      resp =
        conn
        |> post(contract_request_path(conn, :create, @capitation, UUID.generate()), %{
          "signed_content" => params |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(422)

      assert_error(resp, "$.external_contractor_flag", "Invalid external_contractor_flag")
    end

    test "start_date is in the past", %{conn: conn} do
      msp()

      %{
        legal_entity: legal_entity,
        division: division,
        employee: employee,
        party_user: party_user
      } = prepare_data()

      expect(MediaStorageMock, :create_signed_url, 2, fn "HEAD", _, resource, _ ->
        {:ok, %{secret_url: "http://some_url/#{resource}"}}
      end)

      expect(MediaStorageMock, :verify_uploaded_file, 2, fn _, resource ->
        {:ok, %HTTPoison.Response{status_code: 200, headers: [{"ETag", Jason.encode!(resource)}]}}
      end)

      conn =
        conn
        |> put_client_id_header(legal_entity.id)
        |> put_consumer_id_header(party_user.user_id)
        |> put_req_header("drfo", legal_entity.edrpou)

      params =
        division
        |> prepare_capitation_params(employee, to_string(Date.add(Date.utc_today(), 10)))
        |> Map.put("start_date", to_string(Date.utc_today()))

      expect_signed_content(params, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: party_user.party.last_name
      })

      resp =
        conn
        |> post(contract_request_path(conn, :create, @capitation, UUID.generate()), %{
          "signed_content" => params |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(422)

      # temporary it's okay for start_date in past
      # assert_error(resp, "$.start_date", "Start date must be greater than current date")
      assert_error(resp, "$.end_date", "end_date should be equal or greater than start_date")
    end

    test "start_date is too far in the future", %{conn: conn} do
      msp()

      %{
        legal_entity: legal_entity,
        division: division,
        employee: employee,
        party_user: party_user
      } = prepare_data()

      expect(MediaStorageMock, :create_signed_url, 2, fn "HEAD", _, resource, _ ->
        {:ok, %{secret_url: "http://some_url/#{resource}"}}
      end)

      expect(MediaStorageMock, :verify_uploaded_file, 2, fn _, resource ->
        {:ok, %HTTPoison.Response{status_code: 200, headers: [{"ETag", Jason.encode!(resource)}]}}
      end)

      now = Date.utc_today()
      start_date = Date.add(now, 3650)

      params =
        division
        |> prepare_capitation_params(employee, Date.to_iso8601(Date.add(start_date, 1)))
        |> Map.put("start_date", Date.to_iso8601(start_date))

      expect_signed_content(params, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: party_user.party.last_name
      })

      conn
      |> put_client_id_header(legal_entity.id)
      |> put_consumer_id_header(party_user.user_id)
      |> put_req_header("drfo", legal_entity.edrpou)
      |> post(contract_request_path(conn, :create, @capitation, UUID.generate()), %{
        "signed_content" => params |> Jason.encode!() |> Base.encode64(),
        "signed_content_encoding" => "base64"
      })
      |> json_response(422)
      |> assert_error("$.start_date", "Start date must be within this or next year")
    end

    test "invalid end_date", %{conn: conn} do
      msp()

      %{
        legal_entity: legal_entity,
        division: division,
        employee: employee,
        party_user: party_user
      } = prepare_data()

      expect(MediaStorageMock, :create_signed_url, 2, fn "HEAD", _, resource, _ ->
        {:ok, %{secret_url: "http://some_url/#{resource}"}}
      end)

      expect(MediaStorageMock, :verify_uploaded_file, 2, fn _, resource ->
        {:ok, %HTTPoison.Response{status_code: 200, headers: [{"ETag", Jason.encode!(resource)}]}}
      end)

      conn =
        conn
        |> put_client_id_header(legal_entity.id)
        |> put_consumer_id_header(party_user.user_id)
        |> put_req_header("drfo", legal_entity.edrpou)

      start_date = contract_start_date()

      params =
        division
        |> prepare_capitation_params(employee, Date.to_iso8601(Date.add(start_date, 1)))
        |> Map.put("start_date", Date.to_iso8601(start_date))
        |> Map.put("end_date", Date.to_iso8601(Date.add(start_date, 365 * 3)))

      expect_signed_content(params, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: party_user.party.last_name
      })

      resp =
        conn
        |> post(contract_request_path(conn, :create, @capitation, UUID.generate()), %{
          "signed_content" => params |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(422)

      assert_error(resp, "$.end_date", "The year of start_date and and date must be equal")
    end

    test "invalid end_date format", %{conn: conn} do
      msp()

      %{
        legal_entity: legal_entity,
        division: division,
        employee: employee,
        party_user: party_user
      } = prepare_data()

      expect(MediaStorageMock, :create_signed_url, 2, fn "HEAD", _, resource, _ ->
        {:ok, %{secret_url: "http://some_url/#{resource}"}}
      end)

      expect(MediaStorageMock, :verify_uploaded_file, 2, fn _, resource ->
        {:ok, %HTTPoison.Response{status_code: 200, headers: [{"ETag", Jason.encode!(resource)}]}}
      end)

      conn =
        conn
        |> put_client_id_header(legal_entity.id)
        |> put_consumer_id_header(party_user.user_id)
        |> put_req_header("drfo", legal_entity.edrpou)

      start_date = contract_start_date()

      params =
        division
        |> prepare_capitation_params(employee, Date.to_iso8601(Date.add(start_date, 1)))
        |> Map.put("start_date", Date.to_iso8601(start_date))
        |> Map.put("end_date", "2019-02-31")

      expect_signed_content(params, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: party_user.party.last_name
      })

      resp =
        conn
        |> post(contract_request_path(conn, :create, @capitation, UUID.generate()), %{
          "signed_content" => params |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(422)

      assert_error(resp, "$.end_date", "Invalid date format")
    end

    test "contract request overlaps w/ active contract dates (earlier)", %{conn: conn} do
      msp()

      %{
        legal_entity: legal_entity,
        division: division,
        employee: employee,
        user_id: user_id,
        owner: owner,
        party_user: party_user
      } = prepare_data()

      expect(MediaStorageMock, :create_signed_url, 6, fn _, _, resource, _ ->
        {:ok, %{secret_url: "http://some_url/#{resource}"}}
      end)

      expect(MediaStorageMock, :get_signed_content, 2, fn _ -> {:ok, %{body: ""}} end)
      expect(MediaStorageMock, :save_file, 2, fn _, _, _, _ -> {:ok, nil} end)
      expect(MediaStorageMock, :delete_file, 2, fn _ -> {:ok, nil} end)

      expect(MediaStorageMock, :verify_uploaded_file, 2, fn _, resource ->
        {:ok, %HTTPoison.Response{status_code: 200, headers: [{"ETag", Jason.encode!(resource)}]}}
      end)

      now = Date.utc_today()
      contract_request_start_date = Date.add(now, 1)
      contract_request_end_date = Date.add(contract_request_start_date, 10)
      expires_at = Date.to_iso8601(Date.add(contract_request_start_date, 1))

      contract_start_date = Date.add(contract_request_start_date, 5)
      contract_end_date = Date.add(contract_start_date, 10)

      insert(
        :prm,
        :capitation_contract,
        status: CapitationContract.status(:verified),
        contractor_legal_entity: legal_entity,
        start_date: contract_start_date,
        end_date: contract_end_date
      )

      params =
        division
        |> prepare_capitation_params(employee, expires_at)
        |> Map.put("contractor_owner_id", owner.id)
        |> Map.put("start_date", Date.to_iso8601(contract_request_start_date))
        |> Map.put("end_date", Date.to_iso8601(contract_request_end_date))

      expect_signed_content(params, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: party_user.party.last_name
      })

      resp =
        conn
        |> put_client_id_header(legal_entity.id)
        |> put_consumer_id_header(user_id)
        |> put_req_header("drfo", legal_entity.edrpou)
        |> post(contract_request_path(conn, :create, @capitation, UUID.generate()), %{
          "signed_content" => params |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(422)

      assert_error(resp, "Active contract is found. Contract number must be sent in request")
    end

    test "contract request overlaps w/ active contract dates (later)", %{conn: conn} do
      msp()

      %{
        legal_entity: legal_entity,
        division: division,
        employee: employee,
        user_id: user_id,
        owner: owner,
        party_user: party_user
      } = prepare_data()

      expect(MediaStorageMock, :create_signed_url, 6, fn _, _, resource, _ ->
        {:ok, %{secret_url: "http://some_url/#{resource}"}}
      end)

      expect(MediaStorageMock, :get_signed_content, 2, fn _ -> {:ok, %{body: ""}} end)
      expect(MediaStorageMock, :save_file, 2, fn _, _, _, _ -> {:ok, nil} end)
      expect(MediaStorageMock, :delete_file, 2, fn _ -> {:ok, nil} end)

      expect(MediaStorageMock, :verify_uploaded_file, 2, fn _, resource ->
        {:ok, %HTTPoison.Response{status_code: 200, headers: [{"ETag", Jason.encode!(resource)}]}}
      end)

      now = contract_start_date()
      contract_request_start_date = Date.add(now, 1)
      contract_request_end_date = Date.add(contract_request_start_date, 10)
      expires_at = Date.to_iso8601(Date.add(contract_request_start_date, 1))

      contract_start_date = Date.add(contract_request_start_date, -5)
      contract_end_date = Date.add(contract_start_date, 10)

      insert(
        :prm,
        :capitation_contract,
        status: CapitationContract.status(:verified),
        contractor_legal_entity: legal_entity,
        start_date: contract_start_date,
        end_date: contract_end_date
      )

      params =
        division
        |> prepare_capitation_params(employee, expires_at)
        |> Map.put("contractor_owner_id", owner.id)
        |> Map.put("start_date", Date.to_iso8601(contract_request_start_date))
        |> Map.put("end_date", Date.to_iso8601(contract_request_end_date))

      expect_signed_content(params, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: party_user.party.last_name
      })

      resp =
        conn
        |> put_client_id_header(legal_entity.id)
        |> put_consumer_id_header(user_id)
        |> put_req_header("drfo", legal_entity.edrpou)
        |> post(contract_request_path(conn, :create, @capitation, UUID.generate()), %{
          "signed_content" => params |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(422)

      assert_error(resp, "Active contract is found. Contract number must be sent in request")
    end

    test "contract request overlaps w/ active contract dates (coincides)", %{conn: conn} do
      msp()

      %{
        legal_entity: legal_entity,
        division: division,
        employee: employee,
        user_id: user_id,
        owner: owner,
        party_user: party_user
      } = prepare_data()

      expect(MediaStorageMock, :create_signed_url, 6, fn _, _, resource, _ ->
        {:ok, %{secret_url: "http://some_url/#{resource}"}}
      end)

      expect(MediaStorageMock, :get_signed_content, 2, fn _ -> {:ok, %{body: ""}} end)
      expect(MediaStorageMock, :save_file, 2, fn _, _, _, _ -> {:ok, nil} end)
      expect(MediaStorageMock, :delete_file, 2, fn _ -> {:ok, nil} end)

      expect(MediaStorageMock, :verify_uploaded_file, 2, fn _, resource ->
        {:ok, %HTTPoison.Response{status_code: 200, headers: [{"ETag", Jason.encode!(resource)}]}}
      end)

      now = Date.utc_today()
      contract_request_start_date = Date.add(now, 1)
      contract_request_end_date = Date.add(contract_request_start_date, 10)
      expires_at = Date.to_iso8601(Date.add(contract_request_start_date, 1))

      contract_start_date = contract_request_start_date
      contract_end_date = contract_request_end_date

      insert(
        :prm,
        :capitation_contract,
        status: CapitationContract.status(:verified),
        contractor_legal_entity: legal_entity,
        start_date: contract_start_date,
        end_date: contract_end_date
      )

      params =
        division
        |> prepare_capitation_params(employee, expires_at)
        |> Map.put("contractor_owner_id", owner.id)
        |> Map.put("start_date", Date.to_iso8601(contract_request_start_date))
        |> Map.put("end_date", Date.to_iso8601(contract_request_end_date))

      expect_signed_content(params, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: party_user.party.last_name
      })

      resp =
        conn
        |> put_client_id_header(legal_entity.id)
        |> put_consumer_id_header(user_id)
        |> put_req_header("drfo", legal_entity.edrpou)
        |> post(contract_request_path(conn, :create, @capitation, UUID.generate()), %{
          "signed_content" => params |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(422)

      assert_error(resp, "Active contract is found. Contract number must be sent in request")
    end

    test "success create contract request, active contract has passed", %{conn: conn} do
      msp()

      %{
        legal_entity: legal_entity,
        division: division,
        employee: employee,
        user_id: user_id,
        owner: owner,
        party_user: party_user
      } = prepare_data()

      expect(MediaStorageMock, :create_signed_url, 6, fn _, _, resource, _ ->
        {:ok, %{secret_url: "http://some_url/#{resource}"}}
      end)

      expect(MediaStorageMock, :get_signed_content, 2, fn _ -> {:ok, %{body: ""}} end)
      expect(MediaStorageMock, :save_file, 2, fn _, _, _, _ -> {:ok, nil} end)
      expect(MediaStorageMock, :delete_file, 2, fn _ -> {:ok, nil} end)

      expect(MediaStorageMock, :verify_uploaded_file, 2, fn _, resource ->
        {:ok, %HTTPoison.Response{status_code: 200, headers: [{"ETag", Jason.encode!(resource)}]}}
      end)

      expect(MediaStorageMock, :store_signed_content, fn _, _, _, _ ->
        {:ok, "success"}
      end)

      now = Date.utc_today()
      contract_request_start_date = Date.add(now, 1)
      contract_request_end_date = Date.add(contract_request_start_date, 10)
      expires_at = Date.to_iso8601(Date.add(contract_request_start_date, 1))

      contract_start_date = Date.add(contract_request_start_date, -100)
      contract_end_date = Date.add(contract_start_date, 10)

      insert(
        :prm,
        :capitation_contract,
        status: CapitationContract.status(:verified),
        contractor_legal_entity: legal_entity,
        start_date: contract_start_date,
        end_date: contract_end_date
      )

      previous_request = insert(:il, :capitation_contract_request, contractor_legal_entity_id: legal_entity.id)

      params =
        division
        |> prepare_capitation_params(employee, expires_at)
        |> Map.put("contractor_owner_id", owner.id)
        |> Map.put("start_date", Date.to_iso8601(contract_request_start_date))
        |> Map.put("end_date", Date.to_iso8601(contract_request_end_date))
        |> Map.put("previous_request_id", previous_request.id)

      expect_signed_content(params, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: party_user.party.last_name
      })

      contract_request_id = UUID.generate()

      data =
        conn
        |> put_client_id_header(legal_entity.id)
        |> put_consumer_id_header(user_id)
        |> put_req_header("drfo", legal_entity.edrpou)
        |> post(contract_request_path(conn, :create, @capitation, contract_request_id), %{
          "signed_content" => params |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(201)
        |> Map.get("data")

      assert contract_request_id == data["id"]

      Enum.each(data["external_contractors"], fn external_contractor ->
        legal_entity = Map.get(external_contractor, "legal_entity")
        assert Map.has_key?(legal_entity, "id")
        assert Map.has_key?(legal_entity, "name")
      end)
    end

    test "invalid contractor_owner_id", %{conn: conn} do
      msp()

      %{
        legal_entity: legal_entity,
        division: division,
        employee: employee,
        party_user: party_user
      } = prepare_data()

      expect(MediaStorageMock, :create_signed_url, 2, fn "HEAD", _, resource, _ ->
        {:ok, %{secret_url: "http://some_url/#{resource}"}}
      end)

      expect(MediaStorageMock, :verify_uploaded_file, 2, fn _, resource ->
        {:ok, %HTTPoison.Response{status_code: 200, headers: [{"ETag", Jason.encode!(resource)}]}}
      end)

      conn =
        conn
        |> put_client_id_header(legal_entity.id)
        |> put_consumer_id_header(party_user.user_id)
        |> put_req_header("drfo", legal_entity.edrpou)

      start_date = contract_start_date()
      end_date = contract_start_date()

      params =
        division
        |> prepare_capitation_params(employee, Date.to_iso8601(Date.add(start_date, 1)))
        |> Map.put("start_date", Date.to_iso8601(start_date))
        |> Map.put("end_date", Date.to_iso8601(end_date))

      expect_signed_content(params, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: party_user.party.last_name
      })

      resp =
        conn
        |> post(contract_request_path(conn, :create, @capitation, UUID.generate()), %{
          "signed_content" => params |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(422)

      assert_error(
        resp,
        "$.contractor_owner_id",
        "Contractor owner must be active within current legal entity in contract request"
      )
    end

    test "invalid contract number", %{conn: conn} do
      msp()

      %{
        legal_entity: legal_entity,
        division: division,
        employee: employee,
        user_id: user_id,
        owner: owner,
        party_user: party_user
      } = prepare_data()

      expect(MediaStorageMock, :create_signed_url, 2, fn "HEAD", _, resource, _ ->
        {:ok, %{secret_url: "http://some_url/#{resource}"}}
      end)

      expect(MediaStorageMock, :verify_uploaded_file, 2, fn _, resource ->
        {:ok, %HTTPoison.Response{status_code: 200, headers: [{"ETag", Jason.encode!(resource)}]}}
      end)

      start_date = contract_start_date()

      params =
        division
        |> prepare_capitation_params(employee, Date.to_iso8601(Date.add(start_date, 1)))
        |> Map.put("contractor_owner_id", owner.id)
        |> Map.put("contract_number", "invalid")
        |> Map.put("start_date", Date.to_iso8601(start_date))
        |> Map.put("end_date", Date.to_iso8601(Date.add(start_date, 30)))

      expect_signed_content(params, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: party_user.party.last_name
      })

      conn
      |> put_client_id_header(legal_entity.id)
      |> put_consumer_id_header(user_id)
      |> put_req_header("drfo", legal_entity.edrpou)
      |> post(contract_request_path(conn, :create, @capitation, UUID.generate()), %{
        "signed_content" => params |> Jason.encode!() |> Base.encode64(),
        "signed_content_encoding" => "base64"
      })
      |> json_response(422)
      |> assert_error(
        "$.contract_number",
        "string does not match pattern \"^\\d{4}-[\\dAEHKMPTX]{4}-[\\dAEHKMPTX]{4}$\"",
        "format"
      )
    end

    test "success create contract request with contract_number", %{conn: conn} do
      msp()

      %{
        legal_entity: legal_entity,
        division: division,
        employee: employee,
        user_id: user_id,
        owner: owner,
        party_user: party_user
      } = prepare_data()

      expect(MediaStorageMock, :create_signed_url, 6, fn _, _, resource, _ ->
        {:ok, %{secret_url: "http://some_url/#{resource}"}}
      end)

      expect(MediaStorageMock, :get_signed_content, 2, fn _ -> {:ok, %{body: ""}} end)
      expect(MediaStorageMock, :delete_file, 2, fn _ -> {:ok, nil} end)
      expect(MediaStorageMock, :save_file, 2, fn _, _, _, _ -> {:ok, nil} end)

      expect(MediaStorageMock, :verify_uploaded_file, 2, fn _, resource ->
        {:ok, %HTTPoison.Response{status_code: 200, headers: [{"ETag", Jason.encode!(resource)}]}}
      end)

      expect(MediaStorageMock, :store_signed_content, fn _, _, _, _ ->
        {:ok, "success"}
      end)

      start_date = contract_start_date()
      contract_number = NumberGenerator.generate_from_sequence(1, 1)

      insert(
        :prm,
        :capitation_contract,
        contract_number: contract_number,
        status: CapitationContract.status(:verified),
        contractor_legal_entity: legal_entity
      )

      params =
        division
        |> prepare_capitation_params(employee, Date.to_iso8601(Date.add(start_date, 1)))
        |> Map.merge(%{
          "contractor_owner_id" => owner.id,
          "contract_number" => contract_number
        })
        |> Map.drop(~w(start_date end_date))

      expect_signed_content(params, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: party_user.party.last_name
      })

      conn
      |> put_client_id_header(legal_entity.id)
      |> put_consumer_id_header(user_id)
      |> put_req_header("drfo", legal_entity.edrpou)
      |> post(contract_request_path(conn, :create, @capitation, UUID.generate()), %{
        "signed_content" => params |> Jason.encode!() |> Base.encode64(),
        "signed_content_encoding" => "base64"
      })
      |> json_response(201)
      |> Map.get("data")
      |> assert_show_response_schema("contract_request/capitation", "contract_request")
    end

    test "success create contract request without contract_number", %{conn: conn} do
      msp()

      %{
        legal_entity: legal_entity,
        division: division,
        employee: employee,
        user_id: user_id,
        owner: owner,
        party_user: party_user
      } = prepare_data()

      expect(MediaStorageMock, :create_signed_url, 6, fn _, _, resource, _ ->
        {:ok, %{secret_url: "http://some_url/#{resource}"}}
      end)

      expect(MediaStorageMock, :get_signed_content, 2, fn _ -> {:ok, %{body: ""}} end)
      expect(MediaStorageMock, :save_file, 2, fn _, _, _, _ -> {:ok, nil} end)
      expect(MediaStorageMock, :delete_file, 2, fn _ -> {:ok, nil} end)

      expect(MediaStorageMock, :verify_uploaded_file, 2, fn _, resource ->
        {:ok, %HTTPoison.Response{status_code: 200, headers: [{"ETag", Jason.encode!(resource)}]}}
      end)

      expect(MediaStorageMock, :store_signed_content, fn _, _, _, _ ->
        {:ok, "success"}
      end)

      conn =
        conn
        |> put_client_id_header(legal_entity.id)
        |> put_consumer_id_header(user_id)
        |> put_req_header("drfo", legal_entity.edrpou)

      start_date = contract_start_date()

      params =
        division
        |> prepare_capitation_params(employee, Date.to_iso8601(Date.add(start_date, 1)))
        |> Map.put("contractor_owner_id", owner.id)
        |> Map.put("start_date", Date.to_iso8601(start_date))
        |> Map.put("end_date", Date.to_iso8601(Date.add(start_date, 30)))

      expect_signed_content(params, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: party_user.party.last_name
      })

      conn
      |> post(contract_request_path(conn, :create, @capitation, UUID.generate()), %{
        "signed_content" => params |> Jason.encode!() |> Base.encode64(),
        "signed_content_encoding" => "base64"
      })
      |> json_response(201)
      |> Map.get("data")
      |> assert_show_response_schema("contract_request/capitation", "contract_request")
    end

    test "contract employees validation failed", %{conn: conn} do
      msp()

      %{
        legal_entity: legal_entity,
        division: division,
        employee: employee,
        user_id: user_id,
        owner: owner,
        party_user: party_user
      } = prepare_data()

      expect(MediaStorageMock, :create_signed_url, 2, fn "HEAD", _, resource, _ ->
        {:ok, %{secret_url: "http://some_url/#{resource}"}}
      end)

      expect(MediaStorageMock, :verify_uploaded_file, 2, fn _, resource ->
        {:ok, %HTTPoison.Response{status_code: 200, headers: [{"ETag", Jason.encode!(resource)}]}}
      end)

      conn =
        conn
        |> put_client_id_header(legal_entity.id)
        |> put_consumer_id_header(user_id)
        |> put_req_header("drfo", legal_entity.edrpou)

      start_date = contract_start_date()
      end_date = Date.add(start_date, 30)
      expires_at = Date.to_iso8601(Date.add(start_date, 1))

      party_user_out = insert(:prm, :party_user)
      legal_entity_out = insert(:prm, :legal_entity)
      division_out = insert(:prm, :division, legal_entity: legal_entity_out)

      employee_out =
        insert(
          :prm,
          :employee,
          legal_entity_id: legal_entity_out.id,
          employee_type: Employee.type(:owner),
          party: party_user_out.party
        )

      contractor_employee_divisions = [
        %{
          "employee_id" => employee.id,
          "staff_units" => 0.5,
          "declaration_limit" => 2000,
          "division_id" => division.id
        },
        %{
          "employee_id" => employee_out.id,
          "staff_units" => 0.5,
          "declaration_limit" => 2000,
          "division_id" => division_out.id
        },
        %{
          "employee_id" => UUID.generate(),
          "staff_units" => 0.5,
          "declaration_limit" => 2000,
          "division_id" => UUID.generate()
        }
      ]

      params =
        division
        |> prepare_capitation_params(employee, expires_at)
        |> Map.put("contractor_owner_id", owner.id)
        |> Map.put("start_date", Date.to_iso8601(start_date))
        |> Map.put("end_date", Date.to_iso8601(end_date))
        |> Map.put("contractor_employee_divisions", contractor_employee_divisions)

      expect_signed_content(params, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: party_user.party.last_name
      })

      resp =
        conn
        |> post(contract_request_path(conn, :create, @capitation, UUID.generate()), %{
          "signed_content" => params |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(422)

      assert %{
               "invalid" => [
                 %{
                   "entry" => "$.contractor_employee_divisions.[1].employee_id",
                   "rules" => [
                     %{
                       "description" => "Employee must be active DOCTOR",
                       "params" => [],
                       "rule" => "invalid"
                     }
                   ]
                 },
                 %{
                   "entry" => "$.contractor_employee_divisions.[1].employee_id",
                   "rules" => [
                     %{
                       "description" => "Employee should be active Doctor within current legal_entity_id",
                       "params" => [],
                       "rule" => "invalid"
                     }
                   ]
                 },
                 %{
                   "entry" => "$.contractor_employee_divisions.[1].division_id",
                   "rules" => [
                     %{
                       "description" => "Division should be among contractor_divisions",
                       "params" => [],
                       "rule" => "invalid"
                     }
                   ]
                 },
                 %{
                   "entry" => "$.contractor_employee_divisions.[2].employee_id",
                   "rules" => [
                     %{
                       "description" => "Employee not found",
                       "params" => [],
                       "rule" => "invalid"
                     }
                   ]
                 },
                 %{
                   "entry" => "$.contractor_employee_divisions.[2].division_id",
                   "rules" => [
                     %{
                       "description" => "Division should be among contractor_divisions",
                       "params" => [],
                       "rule" => "invalid"
                     }
                   ]
                 }
               ]
             } = resp["error"]
    end
  end

  describe "create contract request by MSP_PHARMACY" do
    setup %{conn: conn} do
      msp_pharmacy()

      stub(MediaStorageMock, :create_signed_url, fn _, _, resource, _ ->
        {:ok, %{secret_url: "http://some_url/#{resource}"}}
      end)

      stub(MediaStorageMock, :get_signed_content, fn _ -> {:ok, %{body: ""}} end)
      stub(MediaStorageMock, :save_file, fn _, _, _, _ -> {:ok, nil} end)
      stub(MediaStorageMock, :delete_file, fn _ -> {:ok, nil} end)

      stub(MediaStorageMock, :verify_uploaded_file, fn _, resource ->
        {:ok, %HTTPoison.Response{status_code: 200, headers: [{"ETag", Jason.encode!(resource)}]}}
      end)

      %{
        legal_entity: legal_entity,
        employee: employee,
        owner: owner,
        user_id: user_id,
        party_user: party_user
      } = prepare_data()

      start_date = contract_start_date()

      params = %{
        "contractor_owner_id" => owner.id,
        "start_date" => Date.to_iso8601(start_date),
        "end_date" => Date.to_iso8601(Date.add(start_date, 30))
      }

      conn =
        conn
        |> put_client_id_header(legal_entity.id)
        |> put_consumer_id_header(user_id)
        |> put_req_header("drfo", legal_entity.edrpou)

      {:ok,
       %{
         conn: conn,
         start_date: start_date,
         legal_entity: legal_entity,
         party_user: party_user,
         params: params,
         employee: employee
       }}
    end

    test "success", context do
      expect(MediaStorageMock, :store_signed_content, fn _, _, _, _ ->
        {:ok, "success"}
      end)

      %{
        conn: conn,
        start_date: start_date,
        legal_entity: legal_entity,
        party_user: party_user,
        params: params,
        employee: employee
      } = context

      division =
        insert(:prm, :division,
          type: Division.type(:ambulant_clinic),
          legal_entity: legal_entity,
          phones: [%{"type" => "MOBILE", "number" => "+380631111111"}]
        )

      params =
        division
        |> prepare_capitation_params(employee, Date.to_iso8601(Date.add(start_date, 1)))
        |> Map.merge(params)

      expect_signed_content(params, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: party_user.party.last_name
      })

      conn
      |> post(contract_request_path(conn, :create, @capitation, UUID.generate()), %{
        "signed_content" => params |> Jason.encode!() |> Base.encode64(),
        "signed_content_encoding" => "base64"
      })
      |> json_response(201)
      |> Map.get("data")
      |> assert_show_response_schema("contract_request/capitation", "contract_request")
    end

    test "invalid division type", context do
      %{
        conn: conn,
        start_date: start_date,
        legal_entity: legal_entity,
        party_user: party_user,
        params: params,
        employee: employee
      } = context

      division =
        insert(:prm, :division,
          type: Division.type(:drugstore),
          legal_entity: legal_entity,
          phones: [%{"type" => "MOBILE", "number" => "+380631111111"}]
        )

      params =
        division
        |> prepare_capitation_params(employee, Date.to_iso8601(Date.add(start_date, 1)))
        |> Map.merge(params)

      expect_signed_content(params, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: party_user.party.last_name
      })

      resp =
        conn
        |> post(contract_request_path(conn, :create, @capitation, UUID.generate()), %{
          "signed_content" => params |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(422)
        |> Map.get("error")

      assert "validation_failed" == resp["type"]
      assert [%{"entry" => "$.contractor_divisions.[0]"}] = resp["invalid"]
    end
  end

  describe "update contract_request" do
    test "user is not NHS ADMIN SIGNER", %{conn: conn} do
      msp()
      contract_request = insert(:il, :capitation_contract_request)

      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "OWNER"}]}}
      end)

      legal_entity = insert(:prm, :legal_entity)
      conn = put_client_id_header(conn, legal_entity.id)

      conn =
        patch(conn, contract_request_path(conn, :update, @capitation, contract_request.id), %{
          "nhs_signer_base" => "на підставі наказу",
          "nhs_contract_price" => 50_000,
          "nhs_payment_method" => "prepayment"
        })

      assert json_response(conn, 403)
    end

    test "no contract_request found", %{conn: conn} do
      msp()

      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      legal_entity = insert(:prm, :legal_entity)
      conn = put_client_id_header(conn, legal_entity.id)

      conn =
        patch(conn, contract_request_path(conn, :update, @capitation, UUID.generate()), %{
          "nhs_signer_base" => "на підставі наказу",
          "nhs_contract_price" => 50_000,
          "nhs_payment_method" => "prepayment"
        })

      assert json_response(conn, 404)
    end

    test "contract_request has wrong status", %{conn: conn} do
      msp()
      contract_request = insert(:il, :capitation_contract_request, status: CapitationContractRequest.status(:signed))

      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      legal_entity = insert(:prm, :legal_entity)
      conn = put_client_id_header(conn, legal_entity.id)

      resp =
        conn
        |> patch(contract_request_path(conn, :update, @capitation, contract_request.id), %{
          "nhs_signer_base" => "на підставі наказу",
          "nhs_contract_price" => 50_000,
          "nhs_payment_method" => "prepayment"
        })
        |> json_response(409)

      assert %{
               "message" => "Incorrect status of contract_request to modify it",
               "type" => "request_conflict"
             } = resp["error"]
    end

    test "success update contract_request", %{conn: conn} do
      msp()
      employee = insert(:prm, :employee)

      contract_request =
        insert(
          :il,
          :capitation_contract_request,
          status: @contract_request_status_in_process,
          start_date: Date.add(Date.utc_today(), 10),
          contractor_owner_id: employee.id
        )

      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      legal_entity = insert(:prm, :legal_entity)
      conn = put_client_id_header(conn, legal_entity.id)

      conn
      |> patch(contract_request_path(conn, :update, @capitation, contract_request.id), %{
        "nhs_signer_base" => "на підставі наказу",
        "nhs_contract_price" => 50_000,
        "nhs_payment_method" => "prepayment"
      })
      |> json_response(200)
      |> Map.get("data")
      |> assert_show_response_schema("contract_request/capitation", "contract_request")
    end

    test "success with zero nhs_contract_price", %{conn: conn} do
      msp()
      employee = insert(:prm, :employee)

      contract_request =
        insert(
          :il,
          :capitation_contract_request,
          status: @contract_request_status_in_process,
          start_date: Date.add(Date.utc_today(), 10),
          contractor_owner_id: employee.id
        )

      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      legal_entity = insert(:prm, :legal_entity)

      request_data = %{
        "nhs_contract_price" => 0,
        "nhs_payment_method" => "prepayment",
        "nhs_signer_base" => "на підставі наказу"
      }

      conn
      |> put_client_id_header(legal_entity.id)
      |> patch(contract_request_path(conn, :update, @capitation, contract_request.id), request_data)
      |> json_response(200)
      |> Map.get("data")
      |> assert_show_response_schema("contract_request/capitation", "contract_request")
    end
  end

  describe "assign contract_request" do
    test "fail: user is not NHS ADMIN SIGNER", %{conn: conn} do
      contract_request = insert(:il, :capitation_contract_request)
      employee = insert(:prm, :employee)

      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "OWNER"}]}}
      end)

      legal_entity = insert(:prm, :legal_entity)
      conn = put_client_id_header(conn, legal_entity.id)

      conn =
        patch(conn, contract_request_path(conn, :update_assignee, @capitation, contract_request.id), %{
          "employee_id" => employee.id
        })

      assert json_response(conn, 403)
    end

    test "fail: no contract_request found", %{conn: conn} do
      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      employee = insert(:prm, :employee)
      legal_entity = insert(:prm, :legal_entity)
      conn = put_client_id_header(conn, legal_entity.id)

      conn =
        patch(conn, contract_request_path(conn, :update_assignee, @capitation, UUID.generate()), %{
          "employee_id" => employee.id
        })

      assert json_response(conn, 404)
    end

    test "fail: invalid employee status", %{conn: conn} do
      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      expect(MithrilMock, :search_user_roles, fn _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      legal_entity = insert(:prm, :legal_entity)
      %{party: party} = insert(:prm, :party_user)
      employee = insert(:prm, :employee, legal_entity_id: legal_entity.id, party: party, status: Employee.status(:new))
      contract_request = insert(:il, :capitation_contract_request, status: CapitationContractRequest.status(:signed))

      assert resp =
               conn
               |> put_client_id_header(legal_entity.id)
               |> patch(contract_request_path(conn, :update_assignee, @capitation, contract_request.id), %{
                 "employee_id" => employee.id
               })
               |> json_response(409)

      assert %{"message" => "Invalid employee status", "type" => "request_conflict"} == resp["error"]
    end

    test "fail: contract_request has wrong status", %{conn: conn} do
      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      expect(MithrilMock, :search_user_roles, fn _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      legal_entity = insert(:prm, :legal_entity)
      %{party: party} = insert(:prm, :party_user)
      employee = insert(:prm, :employee, legal_entity_id: legal_entity.id, party: party)
      contract_request = insert(:il, :capitation_contract_request, status: CapitationContractRequest.status(:signed))

      conn = put_client_id_header(conn, legal_entity.id)

      resp =
        conn
        |> patch(contract_request_path(conn, :update_assignee, @capitation, contract_request.id), %{
          "employee_id" => employee.id
        })
        |> json_response(409)

      assert %{
               "message" => "Incorrect status of contract_request to modify it",
               "type" => "request_conflict"
             } = resp["error"]
    end

    test "fail: employee doesn't belong to legal entity id", %{conn: conn} do
      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      legal_entity = insert(:prm, :legal_entity)
      employee = insert(:prm, :employee)
      contract_request = insert(:il, :capitation_contract_request)

      assert %{"error" => error} =
               conn
               |> put_client_id_header(legal_entity.id)
               |> patch(contract_request_path(conn, :update_assignee, @capitation, contract_request.id), %{
                 "employee_id" => employee.id
               })
               |> json_response(422)

      assert %{"message" => "Invalid legal entity id"} = error
    end

    test "fail: employee doesn't have required role", %{conn: conn} do
      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      expect(MithrilMock, :search_user_roles, fn _, _ ->
        {:ok, %{"data" => []}}
      end)

      legal_entity = insert(:prm, :legal_entity)
      %{party: party} = insert(:prm, :party_user)
      employee = insert(:prm, :employee, legal_entity_id: legal_entity.id, party: party)
      contract_request = insert(:il, :capitation_contract_request, status: CapitationContractRequest.status(:signed))

      conn = put_client_id_header(conn, legal_entity.id)

      resp =
        conn
        |> patch(contract_request_path(conn, :update_assignee, @capitation, contract_request.id), %{
          "employee_id" => employee.id
        })
        |> json_response(403)

      assert %{
               "message" => "Employee doesn't have required role",
               "type" => "forbidden"
             } = resp["error"]
    end

    test "success", %{conn: conn} do
      legal_entity = insert(:prm, :legal_entity)
      party_user = insert(:prm, :party_user)

      employee = insert(:prm, :employee, legal_entity_id: legal_entity.id, party: party_user.party)

      contract_request =
        insert(
          :il,
          :capitation_contract_request,
          contractor_owner_id: employee.id,
          status: @contract_request_status_in_process
        )

      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      expect(MithrilMock, :search_user_roles, fn _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      expect(KafkaMock, :publish_to_event_manager, fn _ -> :ok end)

      conn
      |> put_client_id_header(legal_entity.id)
      |> patch(contract_request_path(conn, :update_assignee, @capitation, contract_request.id), %{
        "employee_id" => employee.id
      })
      |> json_response(200)
      |> Map.get("data")
      |> assert_show_response_schema("contract_request/capitation", "contract_request")
    end
  end

  describe "show contract_request details" do
    setup %{conn: conn} do
      %{id: legal_entity_id_1} = insert(:prm, :legal_entity, type: "MSP")

      %{id: contract_request_id_1} =
        insert(:il, :capitation_contract_request, contractor_legal_entity_id: legal_entity_id_1)

      %{id: legal_entity_id_2} = insert(:prm, :legal_entity, type: "MSP")

      %{id: contract_request_id_2} =
        insert(:il, :capitation_contract_request, contractor_legal_entity_id: legal_entity_id_2)

      {:ok,
       %{
         conn: conn,
         legal_entity_id_1: legal_entity_id_1,
         contract_request_id_1: contract_request_id_1,
         contract_request_id_2: contract_request_id_2
       }}
    end

    test "success showing data for correct MPS client with inactive division", %{conn: conn} do
      msp()

      phones = [%{"type" => "MOBILE", "number" => "+380631111111"}]
      today = Date.utc_today()
      end_date = Date.add(today, 50)
      legal_entity = insert(:prm, :legal_entity, type: "MSP")
      division = insert(:prm, :division, legal_entity: legal_entity, phones: phones)

      inactive_division =
        insert(:prm, :division, status: Division.status(:inactive), legal_entity: legal_entity, phones: phones)

      %{id: contract_request_id} =
        insert(:il, :capitation_contract_request,
          contractor_legal_entity_id: legal_entity.id,
          external_contractors: [
            %{
              "legal_entity_id" => legal_entity.id,
              "divisions" => [
                %{"id" => division.id, "medical_service" => "PHC_SERVICES"},
                %{"id" => inactive_division.id, "medical_service" => "PHC_SERVICES"}
              ],
              "contract" => %{
                "number" => "1234567",
                "issued_at" => to_string(today),
                "expires_at" => to_string(end_date)
              }
            }
          ]
        )

      expect(MediaStorageMock, :create_signed_url, 2, fn _, _, resource_name, id ->
        {:ok, %{secret_url: "http://url.com/#{id}/#{resource_name}"}}
      end)

      expect(MediaStorageMock, :get_signed_content, 2, fn _url -> {:ok, %{status_code: 200, body: ""}} end)

      resp =
        conn
        |> put_client_id_header(legal_entity.id)
        |> get(contract_request_path(conn, :show, @capitation, contract_request_id))
        |> json_response(200)

      division_ids =
        resp
        |> get_in(["data", "external_contractors", Access.all(), "divisions", Access.all(), "id"])
        |> Enum.flat_map(& &1)

      assert division.id in division_ids
      assert inactive_division.id not in division_ids

      Enum.each(resp["urgent"]["documents"], fn urgent_data ->
        assert %{"type" => type} = urgent_data
        assert type == String.upcase(type)

        assert(Map.has_key?(urgent_data, "url"))
      end)
    end

    test "denied showing data for uncorrect MPS client", %{conn: conn} = context do
      msp()

      assert conn
             |> put_client_id_header(context.legal_entity_id_1)
             |> get(contract_request_path(conn, :show, @capitation, context.contract_request_id_2))
             |> json_response(403)
    end

    test "contract_request not found", %{conn: conn} = context do
      msp()

      assert conn
             |> put_client_id_header(context.legal_entity_id_1)
             |> get(contract_request_path(conn, :show, @capitation, UUID.generate()))
             |> json_response(404)
    end

    test "success showing any contract_request for NHS ADMIN client", %{conn: conn} = context do
      nhs(2)

      expect(MediaStorageMock, :create_signed_url, 4, fn _, _, resource_name, id ->
        {:ok, %{secret_url: "http://url.com/#{id}/#{resource_name}"}}
      end)

      expect(MediaStorageMock, :get_signed_content, 4, fn _url -> {:ok, %{status_code: 200, body: ""}} end)

      resp =
        conn
        |> put_client_id_header(UUID.generate())
        |> get(contract_request_path(conn, :show, @capitation, context.contract_request_id_1))
        |> json_response(200)

      assert resp

      Enum.each(resp["urgent"]["documents"], fn urgent_data ->
        assert Map.has_key?(urgent_data, "type")
        assert(Map.has_key?(urgent_data, "url"))
      end)

      resp =
        conn
        |> put_client_id_header(UUID.generate())
        |> get(contract_request_path(conn, :show, @capitation, context.contract_request_id_2))
        |> json_response(200)

      assert resp

      Enum.each(resp["urgent"]["documents"], fn urgent_data ->
        assert Map.has_key?(urgent_data, "type")
        assert(Map.has_key?(urgent_data, "url"))
      end)
    end

    test "contract_request not found for NHS ADMIN client", %{conn: conn} do
      nhs()

      assert conn
             |> put_client_id_header(UUID.generate())
             |> get(contract_request_path(conn, :show, @capitation, UUID.generate()))
             |> json_response(404)
    end
  end

  describe "approve contract_request" do
    test "legal enitity edrpou does not match with signer edrpou", %{conn: conn} do
      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "OWNER"}]}}
      end)

      user_id = UUID.generate()
      party_user = insert(:prm, :party_user, user_id: user_id)
      legal_entity = insert(:prm, :legal_entity)

      contract_request = insert(:il, :capitation_contract_request, contractor_legal_entity_id: legal_entity.id)

      conn =
        conn
        |> put_consumer_id_header(user_id)
        |> put_client_id_header(legal_entity.id)
        |> put_req_header("drfo", legal_entity.edrpou)

      data = %{
        "id" => contract_request.id,
        "next_status" => "APPROVED",
        "contractor_legal_entity" => %{
          "id" => contract_request.contractor_legal_entity_id,
          "name" => legal_entity.name,
          "edrpou" => legal_entity.edrpou
        },
        "text" => "something"
      }

      drfo_signed_content(data, party_user.party.tax_id, party_user.party.last_name)

      resp =
        conn
        |> patch(contract_request_path(conn, :approve, @capitation, contract_request.id), %{
          "signed_content" => data |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(422)

      assert %{
               "invalid" => [
                 %{
                   "entry" => "$.drfo"
                 }
               ],
               "type" => "validation_failed"
             } = resp["error"]
    end

    test "party last name does not match with signer surname", %{conn: conn} do
      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "OWNER"}]}}
      end)

      party_user = insert(:prm, :party_user)
      legal_entity = insert(:prm, :legal_entity)

      contract_request = insert(:il, :capitation_contract_request, contractor_legal_entity_id: legal_entity.id)

      conn =
        conn
        |> put_consumer_id_header(party_user.user_id)
        |> put_client_id_header(legal_entity.id)
        |> put_req_header("drfo", legal_entity.edrpou)

      data = %{
        "id" => contract_request.id,
        "next_status" => "APPROVED",
        "contractor_legal_entity" => %{
          "id" => contract_request.contractor_legal_entity_id,
          "name" => legal_entity.name,
          "edrpou" => legal_entity.edrpou
        },
        "text" => "something"
      }

      expect_signed_content(data, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: "Інше Прізвище"
      })

      resp =
        conn
        |> patch(contract_request_path(conn, :approve, @capitation, contract_request.id), %{
          "signed_content" => data |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(422)

      assert %{
               "invalid" => [
                 %{
                   "entry" => "$.last_name",
                   "rules" => [
                     %{
                       "description" => "Signer surname does not match with current user last_name"
                     }
                   ]
                 }
               ],
               "type" => "validation_failed"
             } = resp["error"]
    end

    test "signer has no surname", %{conn: conn} do
      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "OWNER"}]}}
      end)

      party_user = insert(:prm, :party_user)
      legal_entity = insert(:prm, :legal_entity)

      contract_request = insert(:il, :capitation_contract_request, contractor_legal_entity_id: legal_entity.id)

      conn =
        conn
        |> put_consumer_id_header(party_user.user_id)
        |> put_client_id_header(legal_entity.id)
        |> put_req_header("drfo", legal_entity.edrpou)

      data = %{
        "id" => contract_request.id,
        "next_status" => "APPROVED",
        "contractor_legal_entity" => %{
          "id" => contract_request.contractor_legal_entity_id,
          "name" => legal_entity.name,
          "edrpou" => legal_entity.edrpou
        },
        "text" => "something"
      }

      expect_signed_content(data, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: nil
      })

      resp =
        conn
        |> patch(contract_request_path(conn, :approve, @capitation, contract_request.id), %{
          "signed_content" => data |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(422)

      assert %{
               "invalid" => [
                 %{
                   "entry" => "$.surname",
                   "rules" => [
                     %{
                       "description" => "Signer surname is not exist in sign info"
                     }
                   ]
                 }
               ]
             } = resp["error"]
    end

    test "user party does not exists", %{conn: conn} do
      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "OWNER"}]}}
      end)

      legal_entity = insert(:prm, :legal_entity)

      contract_request = insert(:il, :capitation_contract_request, contractor_legal_entity_id: legal_entity.id)

      conn =
        conn
        |> put_consumer_id_header(UUID.generate())
        |> put_client_id_header(legal_entity.id)
        |> put_req_header("drfo", legal_entity.edrpou)

      data = %{
        "id" => contract_request.id,
        "next_status" => "APPROVED",
        "contractor_legal_entity" => %{
          "id" => contract_request.contractor_legal_entity_id,
          "name" => legal_entity.name,
          "edrpou" => legal_entity.edrpou
        },
        "text" => "something"
      }

      drfo_signed_content(data, [%{drfo: "test", surname: "Підписант"}])

      conn
      |> patch(contract_request_path(conn, :approve, @capitation, contract_request.id), %{
        "signed_content" => data |> Jason.encode!() |> Base.encode64(),
        "signed_content_encoding" => "base64"
      })
      |> json_response(403)
    end

    test "user is not NHS ADMIN SIGNER", %{conn: conn} do
      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "OWNER"}]}}
      end)

      user_id = UUID.generate()
      party_user = insert(:prm, :party_user, user_id: user_id)
      legal_entity = insert(:prm, :legal_entity)

      contract_request = insert(:il, :capitation_contract_request, contractor_legal_entity_id: legal_entity.id)

      conn =
        conn
        |> put_consumer_id_header(user_id)
        |> put_client_id_header(legal_entity.id)
        |> put_req_header("drfo", legal_entity.edrpou)

      data = %{
        "id" => contract_request.id,
        "next_status" => "APPROVED",
        "contractor_legal_entity" => %{
          "id" => contract_request.contractor_legal_entity_id,
          "name" => legal_entity.name,
          "edrpou" => legal_entity.edrpou
        },
        "text" => "something"
      }

      expect_signed_content(data, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: party_user.party.last_name
      })

      conn =
        patch(conn, contract_request_path(conn, :approve, @capitation, contract_request.id), %{
          "signed_content" => data |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })

      assert json_response(conn, 403)
    end

    test "invalid user drfo in DS", %{conn: conn} do
      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "OWNER"}]}}
      end)

      user_id = UUID.generate()
      party_user = insert(:prm, :party_user, user_id: user_id)
      legal_entity = insert(:prm, :legal_entity)
      contract_request = insert(:il, :capitation_contract_request, contractor_legal_entity_id: legal_entity.id)

      conn =
        conn
        |> put_consumer_id_header(user_id)
        |> put_client_id_header(legal_entity.id)
        |> put_req_header("drfo", legal_entity.edrpou)

      data = %{
        "id" => contract_request.id,
        "next_status" => "APPROVED",
        "contractor_legal_entity" => %{
          "id" => contract_request.contractor_legal_entity_id,
          "name" => legal_entity.name,
          "edrpou" => legal_entity.edrpou
        },
        "text" => "something"
      }

      expect_signed_content(data, %{
        edrpou: legal_entity.edrpou,
        drfo: "test",
        surname: party_user.party.last_name
      })

      resp =
        conn
        |> patch(contract_request_path(conn, :approve, @capitation, contract_request.id), %{
          "signed_content" => data |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(422)

      assert %{
               "invalid" => [
                 %{"entry_type" => "request", "rules" => [%{"rule" => "json"}]}
               ],
               "message" => "Does not match the signer drfo",
               "type" => "request_malformed"
             } = resp["error"]
    end

    test "no contract_request found", %{conn: conn} do
      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      user_id = UUID.generate()
      party_user = insert(:prm, :party_user, user_id: user_id)
      legal_entity = insert(:prm, :legal_entity)
      contract_request_id = UUID.generate()

      data = %{
        "id" => contract_request_id,
        "next_status" => "APPROVED",
        "contractor_legal_entity" => %{
          "id" => legal_entity.id,
          "name" => legal_entity.name,
          "edrpou" => legal_entity.edrpou
        },
        "text" => "something"
      }

      expect_signed_content(data, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: party_user.party.last_name
      })

      assert conn
             |> put_consumer_id_header(user_id)
             |> put_client_id_header(legal_entity.id)
             |> patch(contract_request_path(conn, :approve, @capitation, contract_request_id), %{
               "signed_content" => data |> Jason.encode!() |> Base.encode64(),
               "signed_content_encoding" => "base64"
             })
             |> json_response(404)
    end

    test "contract_request has wrong status", %{conn: conn} do
      legal_entity = insert(:prm, :legal_entity, nhs_verified: true)

      contract_request =
        insert(
          :il,
          :capitation_contract_request,
          status: CapitationContractRequest.status(:signed),
          contractor_legal_entity_id: legal_entity.id
        )

      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      expect(MediaStorageMock, :store_signed_content, fn _, _, _, _ ->
        {:ok, "success"}
      end)

      user_id = UUID.generate()
      party_user = insert(:prm, :party_user, user_id: user_id)

      conn =
        conn
        |> put_client_id_header(legal_entity.id)
        |> put_consumer_id_header(user_id)
        |> put_req_header("drfo", legal_entity.edrpou)

      data = %{
        "id" => contract_request.id,
        "next_status" => "APPROVED",
        "contractor_legal_entity" => %{
          "id" => legal_entity.id,
          "name" => legal_entity.name,
          "edrpou" => legal_entity.edrpou
        },
        "text" => "something"
      }

      expect_signed_content(data, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: party_user.party.last_name
      })

      resp =
        conn
        |> patch(contract_request_path(conn, :approve, @capitation, contract_request.id), %{
          "signed_content" => data |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(409)

      assert %{
               "message" => "Incorrect status of contract_request to modify it",
               "type" => "request_conflict"
             } = resp["error"]
    end

    test "contractor_legal_entity not found", %{conn: conn} do
      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      user_id = UUID.generate()
      party_user = insert(:prm, :party_user, user_id: user_id)
      legal_entity = insert(:prm, :legal_entity)

      contract_request = insert(:il, :capitation_contract_request, contractor_legal_entity_id: UUID.generate())

      data = %{
        "id" => contract_request.id,
        "next_status" => "APPROVED",
        "contractor_legal_entity" => %{
          "id" => contract_request.contractor_legal_entity_id,
          "name" => legal_entity.name,
          "edrpou" => legal_entity.edrpou
        },
        "text" => "something"
      }

      expect_signed_content(data, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: party_user.party.last_name
      })

      conn
      |> put_consumer_id_header(user_id)
      |> put_client_id_header(legal_entity.id)
      |> put_req_header("drfo", legal_entity.edrpou)
      |> patch(contract_request_path(conn, :approve, @capitation, contract_request.id), %{
        "signed_content" => data |> Jason.encode!() |> Base.encode64(),
        "signed_content_encoding" => "base64"
      })
      |> json_response(404)
    end

    test "contractor_legal_entity is not active", %{conn: conn} do
      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      expect(MediaStorageMock, :store_signed_content, fn _, _, _, _ ->
        {:ok, "success"}
      end)

      user_id = UUID.generate()
      party_user = insert(:prm, :party_user, user_id: user_id)
      legal_entity = insert(:prm, :legal_entity, status: LegalEntity.status(:closed), nhs_verified: true)

      contract_request = insert(:il, :capitation_contract_request, contractor_legal_entity_id: legal_entity.id)

      legal_entity = insert(:prm, :legal_entity)

      conn =
        conn
        |> put_consumer_id_header(user_id)
        |> put_client_id_header(legal_entity.id)
        |> put_req_header("drfo", legal_entity.edrpou)

      data = %{
        "id" => contract_request.id,
        "next_status" => "APPROVED",
        "contractor_legal_entity" => %{
          "id" => contract_request.contractor_legal_entity_id,
          "name" => legal_entity.name,
          "edrpou" => legal_entity.edrpou
        },
        "text" => "something"
      }

      expect_signed_content(data, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: party_user.party.last_name
      })

      resp =
        conn
        |> patch(contract_request_path(conn, :approve, @capitation, contract_request.id), %{
          "signed_content" => data |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(422)

      assert %{
               "invalid" => [
                 %{
                   "entry" => "$.contractor_legal_entity_id",
                   "entry_type" => "json_data_property",
                   "rules" => [
                     %{
                       "description" => "Legal entity is not active",
                       "params" => [],
                       "rule" => "invalid"
                     }
                   ]
                 }
               ]
             } = resp["error"]
    end

    test "contractor_owner_id not found", %{conn: conn} do
      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      expect(MediaStorageMock, :store_signed_content, fn _, _, _, _ ->
        {:ok, "success"}
      end)

      user_id = UUID.generate()
      party_user = insert(:prm, :party_user, user_id: user_id)
      legal_entity = insert(:prm, :legal_entity, nhs_verified: true)

      contract_request =
        insert(
          :il,
          :capitation_contract_request,
          status: @contract_request_status_in_process,
          contractor_legal_entity_id: legal_entity.id,
          contractor_owner_id: UUID.generate()
        )

      conn =
        conn
        |> put_consumer_id_header(user_id)
        |> put_client_id_header(legal_entity.id)
        |> put_req_header("drfo", legal_entity.edrpou)

      data = %{
        "id" => contract_request.id,
        "next_status" => "APPROVED",
        "contractor_legal_entity" => %{
          "id" => contract_request.contractor_legal_entity_id,
          "name" => legal_entity.name,
          "edrpou" => legal_entity.edrpou
        },
        "text" => "something"
      }

      expect_signed_content(data, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: party_user.party.last_name
      })

      resp =
        conn
        |> patch(contract_request_path(conn, :approve, @capitation, contract_request.id), %{
          "signed_content" => data |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(422)

      assert %{
               "invalid" => [
                 %{
                   "entry" => "$.contractor_owner_id",
                   "entry_type" => "json_data_property",
                   "rules" => [
                     %{
                       "description" =>
                         "Contractor owner must be active within current legal entity in contract request",
                       "params" => [],
                       "rule" => "invalid"
                     }
                   ]
                 }
               ]
             } = resp["error"]
    end

    test "contractor_owner_id has invalid status", %{conn: conn} do
      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      expect(MediaStorageMock, :store_signed_content, fn _, _, _, _ ->
        {:ok, "success"}
      end)

      user_id = UUID.generate()
      party_user = insert(:prm, :party_user, user_id: user_id)
      legal_entity = insert(:prm, :legal_entity, nhs_verified: true)
      employee = insert(:prm, :employee, status: Employee.status(:new))

      contract_request =
        insert(
          :il,
          :capitation_contract_request,
          status: @contract_request_status_in_process,
          contractor_legal_entity_id: legal_entity.id,
          contractor_owner_id: employee.id
        )

      conn =
        conn
        |> put_client_id_header(legal_entity.id)
        |> put_consumer_id_header(user_id)
        |> put_req_header("drfo", legal_entity.edrpou)

      data = %{
        "id" => contract_request.id,
        "next_status" => "APPROVED",
        "contractor_legal_entity" => %{
          "id" => contract_request.contractor_legal_entity_id,
          "name" => legal_entity.name,
          "edrpou" => legal_entity.edrpou
        },
        "text" => "something"
      }

      expect_signed_content(data, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: party_user.party.last_name
      })

      # query path without contract type
      resp =
        conn
        |> patch("/api/contract_requests/#{contract_request.id}/actions/approve", %{
          "signed_content" => data |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(422)

      assert %{
               "invalid" => [
                 %{
                   "entry" => "$.contractor_owner_id",
                   "entry_type" => "json_data_property",
                   "rules" => [
                     %{
                       "description" =>
                         "Contractor owner must be active within current legal entity in contract request",
                       "params" => [],
                       "rule" => "invalid"
                     }
                   ]
                 }
               ]
             } = resp["error"]
    end

    test "employee legal_entity_id doesn't match contractor_legal_entity_id", %{conn: conn} do
      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      expect(MediaStorageMock, :store_signed_content, fn _, _, _, _ ->
        {:ok, "success"}
      end)

      user_id = UUID.generate()
      party_user = insert(:prm, :party_user, user_id: user_id)
      legal_entity = insert(:prm, :legal_entity, nhs_verified: true)
      employee = insert(:prm, :employee)

      contract_request =
        insert(
          :il,
          :capitation_contract_request,
          status: @contract_request_status_in_process,
          contractor_legal_entity_id: legal_entity.id,
          contractor_owner_id: employee.id
        )

      conn =
        conn
        |> put_client_id_header(legal_entity.id)
        |> put_consumer_id_header(user_id)
        |> put_req_header("drfo", legal_entity.edrpou)

      data = %{
        "id" => contract_request.id,
        "next_status" => "APPROVED",
        "contractor_legal_entity" => %{
          "id" => contract_request.contractor_legal_entity_id,
          "name" => legal_entity.name,
          "edrpou" => legal_entity.edrpou
        },
        "text" => "something"
      }

      expect_signed_content(data, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: party_user.party.last_name
      })

      resp =
        conn
        |> patch(contract_request_path(conn, :approve, @capitation, contract_request.id), %{
          "signed_content" => data |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(422)

      assert %{
               "invalid" => [
                 %{
                   "entry" => "$.contractor_owner_id",
                   "entry_type" => "json_data_property",
                   "rules" => [
                     %{
                       "description" =>
                         "Contractor owner must be active within current legal entity in contract request",
                       "params" => [],
                       "rule" => "invalid"
                     }
                   ]
                 }
               ]
             } = resp["error"]
    end

    test "employee is not owner", %{conn: conn} do
      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      expect(MediaStorageMock, :store_signed_content, fn _, _, _, _ ->
        {:ok, "success"}
      end)

      legal_entity = insert(:prm, :legal_entity, nhs_verified: true)
      employee = insert(:prm, :employee, legal_entity_id: legal_entity.id)
      user_id = UUID.generate()
      party_user = insert(:prm, :party_user, user_id: user_id)

      contract_request =
        insert(
          :il,
          :capitation_contract_request,
          status: @contract_request_status_in_process,
          contractor_legal_entity_id: legal_entity.id,
          contractor_owner_id: employee.id
        )

      data = %{
        "id" => contract_request.id,
        "next_status" => "APPROVED",
        "contractor_legal_entity" => %{
          "id" => contract_request.contractor_legal_entity_id,
          "name" => legal_entity.name,
          "edrpou" => legal_entity.edrpou
        },
        "text" => "something"
      }

      conn =
        conn
        |> put_consumer_id_header(user_id)
        |> put_client_id_header(legal_entity.id)
        |> put_req_header("drfo", legal_entity.edrpou)

      expect_signed_content(data, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: party_user.party.last_name
      })

      resp =
        conn
        |> patch(contract_request_path(conn, :approve, @capitation, contract_request.id), %{
          "signed_content" => data |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(422)

      assert %{
               "invalid" => [
                 %{
                   "entry" => "$.contractor_owner_id",
                   "entry_type" => "json_data_property",
                   "rules" => [
                     %{
                       "description" =>
                         "Contractor owner must be active within current legal entity in contract request",
                       "params" => [],
                       "rule" => "invalid"
                     }
                   ]
                 }
               ]
             } = resp["error"]
    end

    test "contractor divisions validation errors mix", %{conn: conn} do
      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      expect(MediaStorageMock, :store_signed_content, fn _, _, _, _ ->
        {:ok, "success"}
      end)

      user_id = UUID.generate()
      legal_entity = insert(:prm, :legal_entity, nhs_verified: true)
      party_user = insert(:prm, :party_user, user_id: user_id)
      contractor_division_1 = insert(:prm, :division, legal_entity: legal_entity)
      contractor_division_2 = insert(:prm, :division, legal_entity: legal_entity)

      employee =
        insert(
          :prm,
          :employee,
          legal_entity_id: legal_entity.id,
          employee_type: Employee.type(:owner),
          party: party_user.party
        )

      contract_request =
        insert(
          :il,
          :capitation_contract_request,
          status: @contract_request_status_in_process,
          contractor_legal_entity_id: legal_entity.id,
          contractor_owner_id: employee.id,
          contractor_divisions: [contractor_division_1.id, contractor_division_2.id],
          contractor_employee_divisions: [
            %{division_id: contractor_division_1.id, employee_id: employee.id},
            %{division_id: contractor_division_2.id, employee_id: UUID.generate()},
            %{division_id: UUID.generate(), employee_id: UUID.generate()}
          ],
          nhs_signer_id: nil
        )

      conn =
        conn
        |> put_client_id_header(legal_entity.id)
        |> put_consumer_id_header(user_id)
        |> put_req_header("drfo", legal_entity.edrpou)

      data = %{
        "id" => contract_request.id,
        "next_status" => "APPROVED",
        "contractor_legal_entity" => %{
          "id" => contract_request.contractor_legal_entity_id,
          "name" => legal_entity.name,
          "edrpou" => legal_entity.edrpou
        },
        "text" => "something"
      }

      expect_signed_content(data, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: party_user.party.last_name
      })

      resp =
        conn
        |> patch(contract_request_path(conn, :approve, @capitation, contract_request.id), %{
          "signed_content" => data |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(422)

      assert %{
               "invalid" => [
                 %{
                   "entry" => "$.contractor_employee_divisions.[0].employee_id",
                   "rules" => [
                     %{
                       "description" => "Employee must be active DOCTOR",
                       "params" => [],
                       "rule" => "invalid"
                     }
                   ]
                 },
                 %{
                   "entry" => "$.contractor_employee_divisions.[1].employee_id",
                   "rules" => [
                     %{
                       "description" => "Employee not found",
                       "params" => [],
                       "rule" => "invalid"
                     }
                   ]
                 },
                 %{
                   "entry" => "$.contractor_employee_divisions.[2].employee_id",
                   "rules" => [
                     %{
                       "description" => "Employee not found",
                       "params" => [],
                       "rule" => "invalid"
                     }
                   ]
                 },
                 %{
                   "entry" => "$.contractor_employee_divisions.[2].division_id",
                   "rules" => [
                     %{
                       "description" => "Division should be among contractor_divisions",
                       "params" => [],
                       "rule" => "invalid"
                     }
                   ]
                 }
               ]
             } = resp["error"]
    end

    test "invalid start date", %{conn: conn} do
      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      expect(MediaStorageMock, :store_signed_content, fn _, _, _, _ ->
        {:ok, "success"}
      end)

      user_id = UUID.generate()
      legal_entity = insert(:prm, :legal_entity, nhs_verified: true)
      party_user = insert(:prm, :party_user, user_id: user_id)

      employee_owner =
        insert(
          :prm,
          :employee,
          legal_entity_id: legal_entity.id,
          employee_type: Employee.type(:owner),
          party: party_user.party
        )

      division = insert(:prm, :division, legal_entity: legal_entity)

      employee_doctor = insert(:prm, :employee, legal_entity_id: legal_entity.id, division: division)

      now = Date.utc_today()
      start_date = Date.add(now, 3650)

      contract_request =
        insert(
          :il,
          :capitation_contract_request,
          status: @contract_request_status_in_process,
          contractor_legal_entity_id: legal_entity.id,
          contractor_owner_id: employee_owner.id,
          start_date: start_date,
          contractor_divisions: [division.id],
          contractor_employee_divisions: [
            %{
              "employee_id" => employee_doctor.id,
              "staff_units" => 0.5,
              "declaration_limit" => 2000,
              "division_id" => division.id
            }
          ],
          nhs_signer_id: nil
        )

      conn =
        conn
        |> put_client_id_header(legal_entity.id)
        |> put_consumer_id_header(user_id)
        |> put_req_header("drfo", legal_entity.edrpou)

      data = %{
        "id" => contract_request.id,
        "next_status" => "APPROVED",
        "contractor_legal_entity" => %{
          "id" => contract_request.contractor_legal_entity_id,
          "name" => legal_entity.name,
          "edrpou" => legal_entity.edrpou
        },
        "text" => "something"
      }

      expect_signed_content(data, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: party_user.party.last_name
      })

      resp =
        conn
        |> patch(contract_request_path(conn, :approve, @capitation, contract_request.id), %{
          "signed_content" => data |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(422)

      assert %{
               "invalid" => [
                 %{
                   "entry" => "$.start_date",
                   "entry_type" => "json_data_property",
                   "rules" => [
                     %{
                       "description" => "Start date must be within this or next year",
                       "params" => [],
                       "rule" => "invalid"
                     }
                   ]
                 }
               ]
             } = resp["error"]
    end

    test "success approve contract request", %{conn: conn} do
      insert(:il, :dictionary, name: "SETTLEMENT_TYPE", values: %{})
      insert(:il, :dictionary, name: "STREET_TYPE", values: %{})
      insert(:il, :dictionary, name: "SPECIALITY_TYPE", values: %{})

      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      expect(MediaStorageMock, :store_signed_content, fn _, _, _, _ ->
        {:ok, "success"}
      end)

      expect(KafkaMock, :publish_to_event_manager, fn _ -> :ok end)

      user_id = UUID.generate()
      party_user = insert(:prm, :party_user, user_id: user_id)
      legal_entity = insert(:prm, :legal_entity, nhs_verified: true)

      employee_owner =
        insert(
          :prm,
          :employee,
          legal_entity_id: legal_entity.id,
          employee_type: Employee.type(:owner),
          party: party_user.party
        )

      employee_admin =
        insert(
          :prm,
          :employee,
          legal_entity_id: legal_entity.id,
          employee_type: Employee.type(:admin),
          party: party_user.party
        )

      division =
        insert(
          :prm,
          :division,
          legal_entity: legal_entity,
          phones: [%{"type" => "MOBILE", "number" => "+380631111111"}]
        )

      employee_doctor = insert(:prm, :employee, legal_entity_id: legal_entity.id, division: division)

      start_date = contract_start_date()

      contract_request =
        insert(
          :il,
          :capitation_contract_request,
          status: @contract_request_status_in_process,
          nhs_signer_id: employee_admin.id,
          nhs_legal_entity_id: legal_entity.id,
          contractor_legal_entity_id: legal_entity.id,
          contractor_owner_id: employee_owner.id,
          contractor_divisions: [division.id],
          contractor_employee_divisions: [
            %{
              "employee_id" => employee_doctor.id,
              "staff_units" => 0.5,
              "declaration_limit" => 2000,
              "division_id" => division.id
            }
          ],
          start_date: start_date
        )

      employee_owner
      |> Ecto.Changeset.change(status: Employee.status(:dismissed))
      |> Core.PRMRepo.update()

      conn =
        conn
        |> put_client_id_header(legal_entity.id)
        |> put_consumer_id_header(user_id)
        |> put_req_header("drfo", legal_entity.edrpou)

      data = %{
        "id" => contract_request.id,
        "next_status" => "APPROVED",
        "contractor_legal_entity" => %{
          "id" => contract_request.contractor_legal_entity_id,
          "name" => legal_entity.name,
          "edrpou" => legal_entity.edrpou
        },
        "text" => "something"
      }

      expect_signed_content(data, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: party_user.party.last_name
      })

      conn
      |> patch(contract_request_path(conn, :approve, @capitation, contract_request.id), %{
        "signed_content" => data |> Jason.encode!() |> Base.encode64(),
        "signed_content_encoding" => "base64"
      })
      |> json_response(200)
      |> Map.get("data")
      |> assert_show_response_schema("contract_request/capitation", "contract_request")
    end
  end

  describe "approve by msp" do
    test "success approve by msp", %{conn: conn} do
      user_id = UUID.generate()
      party_user = insert(:prm, :party_user, user_id: user_id)
      legal_entity = insert(:prm, :legal_entity, nhs_verified: true)

      expect(KafkaMock, :publish_to_event_manager, fn _ -> :ok end)

      employee_owner =
        insert(
          :prm,
          :employee,
          legal_entity_id: legal_entity.id,
          employee_type: Employee.type(:owner),
          party: party_user.party
        )

      division =
        insert(
          :prm,
          :division,
          legal_entity: legal_entity,
          phones: [%{"type" => "MOBILE", "number" => "+380631111111"}]
        )

      employee_doctor = insert(:prm, :employee, legal_entity_id: legal_entity.id, division: division)

      start_date = contract_start_date()

      contract_request =
        insert(
          :il,
          :capitation_contract_request,
          status: CapitationContractRequest.status(:approved),
          contractor_legal_entity_id: legal_entity.id,
          contractor_owner_id: employee_owner.id,
          contractor_divisions: [division.id],
          contractor_employee_divisions: [
            %{
              "employee_id" => employee_doctor.id,
              "staff_units" => 0.5,
              "declaration_limit" => 2000,
              "division_id" => division.id
            }
          ],
          start_date: start_date
        )

      conn
      |> put_client_id_header(legal_entity.id)
      |> put_consumer_id_header(user_id)
      |> patch(contract_request_path(conn, :approve_msp, @capitation, contract_request.id))
      |> json_response(200)
      |> Map.get("data")
      |> assert_show_response_schema("contract_request/capitation", "contract_request")
    end

    test "invalid contractor_owner_id", %{conn: conn} do
      legal_entity = insert(:prm, :legal_entity)

      contract_request =
        insert(
          :il,
          :capitation_contract_request,
          status: CapitationContractRequest.status(:approved)
        )

      conn = put_client_id_header(conn, legal_entity.id)
      conn = patch(conn, contract_request_path(conn, :approve_msp, @capitation, contract_request.id))
      assert json_response(conn, 403)
    end

    test "contract_request not found", %{conn: conn} do
      conn = put_client_id_header(conn, UUID.generate())
      conn = patch(conn, contract_request_path(conn, :approve_msp, @capitation, UUID.generate()))
      assert json_response(conn, 404)
    end

    test "fail with incorrect contractor legal entity status", %{conn: conn} do
      user_id = UUID.generate()
      party_user = insert(:prm, :party_user, user_id: user_id)
      legal_entity = insert(:prm, :legal_entity, status: LegalEntity.status(:closed), nhs_verified: true)

      expect(KafkaMock, :publish_to_event_manager, fn _ -> :ok end)

      employee_owner =
        insert(
          :prm,
          :employee,
          legal_entity_id: legal_entity.id,
          employee_type: Employee.type(:owner),
          party: party_user.party
        )

      division =
        insert(
          :prm,
          :division,
          legal_entity: legal_entity,
          phones: [%{"type" => "MOBILE", "number" => "+380631111111"}]
        )

      employee_doctor = insert(:prm, :employee, legal_entity_id: legal_entity.id, division: division)

      start_date = contract_start_date()

      contract_request =
        insert(
          :il,
          :capitation_contract_request,
          status: CapitationContractRequest.status(:approved),
          contractor_legal_entity_id: legal_entity.id,
          contractor_owner_id: employee_owner.id,
          contractor_divisions: [division.id],
          contractor_employee_divisions: [
            %{
              "employee_id" => employee_doctor.id,
              "staff_units" => 0.5,
              "declaration_limit" => 2000,
              "division_id" => division.id
            }
          ],
          start_date: start_date
        )

      resp =
        conn
        |> put_client_id_header(legal_entity.id)
        |> put_consumer_id_header(user_id)
        |> patch(contract_request_path(conn, :approve_msp, @capitation, contract_request.id))
        |> json_response(422)

      assert %{
               "type" => "validation_failed",
               "invalid" => [
                 %{
                   "entry" => "$.contractor_legal_entity_id",
                   "rules" => [%{"description" => "Legal entity is not active"}]
                 }
               ]
             } = resp["error"]
    end

    test "fail with contractor legal entity not passed NHS verification", %{conn: conn} do
      user_id = UUID.generate()
      party_user = insert(:prm, :party_user, user_id: user_id)
      legal_entity = insert(:prm, :legal_entity, nhs_verified: false)

      expect(KafkaMock, :publish_to_event_manager, fn _ -> :ok end)

      employee_owner =
        insert(
          :prm,
          :employee,
          legal_entity_id: legal_entity.id,
          employee_type: Employee.type(:owner),
          party: party_user.party
        )

      division =
        insert(
          :prm,
          :division,
          legal_entity: legal_entity,
          phones: [%{"type" => "MOBILE", "number" => "+380631111111"}]
        )

      employee_doctor = insert(:prm, :employee, legal_entity_id: legal_entity.id, division: division)

      start_date = contract_start_date()

      contract_request =
        insert(
          :il,
          :capitation_contract_request,
          status: CapitationContractRequest.status(:approved),
          contractor_legal_entity_id: legal_entity.id,
          contractor_owner_id: employee_owner.id,
          contractor_divisions: [division.id],
          contractor_employee_divisions: [
            %{
              "employee_id" => employee_doctor.id,
              "staff_units" => 0.5,
              "declaration_limit" => 2000,
              "division_id" => division.id
            }
          ],
          start_date: start_date
        )

      resp =
        conn
        |> put_client_id_header(legal_entity.id)
        |> put_consumer_id_header(user_id)
        |> patch(contract_request_path(conn, :approve_msp, @capitation, contract_request.id))
        |> json_response(422)

      assert %{
               "type" => "validation_failed",
               "invalid" => [
                 %{
                   "entry" => "$.contractor_legal_entity_id",
                   "rules" => [%{"description" => "Legal entity is not verified by NHS"}]
                 }
               ]
             } = resp["error"]
    end
  end

  describe "terminate contract_request" do
    test "success contract_request terminating", %{conn: conn} do
      msp(4)
      user_id = UUID.generate()
      party_user = insert(:prm, :party_user, user_id: user_id)
      legal_entity = insert(:prm, :legal_entity)

      expect(KafkaMock, :publish_to_event_manager, 4, fn _ -> :ok end)

      employee_owner =
        insert(
          :prm,
          :employee,
          legal_entity_id: legal_entity.id,
          employee_type: Employee.type(:owner),
          party: party_user.party
        )

      division = insert(:prm, :division, legal_entity: legal_entity)

      employee_doctor = insert(:prm, :employee, legal_entity_id: legal_entity.id, division: division)

      for status <- @allowed_statuses_for_termination do
        contract_request =
          insert(
            :il,
            :capitation_contract_request,
            status: status,
            contractor_legal_entity_id: legal_entity.id,
            contractor_owner_id: employee_owner.id,
            contractor_employee_divisions: [
              %{
                "employee_id" => employee_doctor.id,
                "staff_units" => 0.5,
                "declaration_limit" => 2000,
                "division_id" => division.id
              }
            ]
          )

        resp =
          conn
          |> put_client_id_header(legal_entity.id)
          |> put_consumer_id_header(user_id)
          |> patch(contract_request_path(conn, :terminate, @capitation, contract_request.id), %{
            "status_reason" => "Неправильний період контракту"
          })
          |> json_response(200)
          |> Map.get("data")
          |> assert_show_response_schema("contract_request/capitation", "contract_request")

        assert resp["status"] == CapitationContractRequest.status(:terminated)
      end
    end

    test "contract_request not found", %{conn: conn} do
      msp()
      user_id = UUID.generate()
      legal_entity = insert(:prm, :legal_entity)

      assert conn
             |> put_client_id_header(legal_entity.id)
             |> put_consumer_id_header(user_id)
             |> patch(contract_request_path(conn, :terminate, @capitation, UUID.generate()), %{
               "status_reason" => "Неправильний період контракту"
             })
             |> json_response(404)
    end

    test "legal_entity_id doesn't match contractor_legal_entity_id", %{conn: conn} do
      msp()
      legal_entity = insert(:prm, :legal_entity)

      contract_request = insert(:il, :capitation_contract_request, contractor_legal_entity_id: UUID.generate())

      resp =
        conn
        |> put_client_id_header(legal_entity.id)
        |> patch(contract_request_path(conn, :terminate, @capitation, contract_request.id), %{
          "status_reason" => "Неправильний період контракту"
        })
        |> json_response(403)

      assert %{"message" => "User is not allowed to perform this action"} = resp["error"]
    end

    test "employee legal_entity_id doesn't match contractor_legal_entity_id", %{conn: conn} do
      msp()
      legal_entity = insert(:prm, :legal_entity)
      employee = insert(:prm, :employee)

      contract_request =
        insert(
          :il,
          :capitation_contract_request,
          contractor_legal_entity_id: legal_entity.id,
          contractor_owner_id: employee.id
        )

      resp =
        conn
        |> put_client_id_header(legal_entity.id)
        |> patch(contract_request_path(conn, :terminate, @capitation, contract_request.id), %{
          "status_reason" => "Неправильний період контракту"
        })
        |> json_response(403)

      assert %{"message" => "User is not allowed to perform this action"} = resp["error"]
    end

    test "employee is not owner", %{conn: conn} do
      msp()
      legal_entity = insert(:prm, :legal_entity)
      employee = insert(:prm, :employee, legal_entity_id: legal_entity.id)

      contract_request =
        insert(
          :il,
          :capitation_contract_request,
          contractor_legal_entity_id: legal_entity.id,
          contractor_owner_id: employee.id
        )

      resp =
        conn
        |> put_client_id_header(legal_entity.id)
        |> patch(contract_request_path(conn, :terminate, @capitation, contract_request.id), %{
          "status_reason" => "Неправильний період контракту"
        })
        |> json_response(403)

      assert %{"message" => "User is not allowed to perform this action"} = resp["error"]
    end

    test "contract_request has wrong status", %{conn: conn} do
      msp(3)
      user_id = UUID.generate()
      party_user = insert(:prm, :party_user, user_id: user_id)
      legal_entity = insert(:prm, :legal_entity)

      employee_owner =
        insert(
          :prm,
          :employee,
          legal_entity_id: legal_entity.id,
          employee_type: Employee.type(:owner),
          party: party_user.party
        )

      division = insert(:prm, :division, legal_entity: legal_entity)

      employee_doctor = insert(:prm, :employee, legal_entity_id: legal_entity.id, division: division)

      for status <- @forbidden_statuses_for_termination do
        contract_request =
          insert(
            :il,
            :capitation_contract_request,
            status: status,
            contractor_legal_entity_id: legal_entity.id,
            contractor_owner_id: employee_owner.id,
            contractor_employee_divisions: [
              %{
                "employee_id" => employee_doctor.id,
                "staff_units" => 0.5,
                "declaration_limit" => 2000,
                "division_id" => division.id
              }
            ]
          )

        resp =
          conn
          |> put_client_id_header(legal_entity.id)
          |> put_consumer_id_header(user_id)
          |> patch(contract_request_path(conn, :terminate, @capitation, contract_request.id), %{
            "status_reason" => "Неправильний період контракту"
          })
          |> json_response(422)

        assert %{
                 "invalid" => [
                   %{"entry_type" => "request", "rules" => [%{"rule" => "json"}]}
                 ],
                 "message" => "Incorrect status of contract_request to modify it",
                 "type" => "request_malformed"
               } = resp["error"]
      end
    end

    test "event manager successful registration", %{conn: conn} do
      msp()
      user_id = UUID.generate()
      party_user = insert(:prm, :party_user, user_id: user_id)
      legal_entity = insert(:prm, :legal_entity)

      expect(KafkaMock, :publish_to_event_manager, fn _ -> :ok end)

      employee_owner =
        insert(
          :prm,
          :employee,
          legal_entity_id: legal_entity.id,
          employee_type: Employee.type(:owner),
          party: party_user.party
        )

      division = insert(:prm, :division, legal_entity: legal_entity)

      employee_doctor = insert(:prm, :employee, legal_entity_id: legal_entity.id, division: division)

      contract_request =
        insert(
          :il,
          :capitation_contract_request,
          contractor_legal_entity_id: legal_entity.id,
          contractor_owner_id: employee_owner.id,
          contractor_employee_divisions: [
            %{
              "employee_id" => employee_doctor.id,
              "staff_units" => 0.5,
              "declaration_limit" => 2000,
              "division_id" => division.id
            }
          ]
        )

      assert conn
             |> put_client_id_header(legal_entity.id)
             |> put_consumer_id_header(user_id)
             |> patch(contract_request_path(conn, :terminate, @capitation, contract_request.id), %{
               "status_reason" => "Неправильний період контракту"
             })
             |> json_response(200)
    end
  end

  describe "search capitation contract request" do
    setup do
      nhs_signer_id = UUID.generate()
      contract_number = UUID.generate()
      contractor_owner_id = UUID.generate()
      legal_entity_id_1 = UUID.generate()
      legal_entity_id_2 = UUID.generate()

      insert(:prm, :legal_entity, type: "MSP", id: legal_entity_id_1)
      insert(:prm, :legal_entity, type: "NHS", id: legal_entity_id_2)
      insert(:il, :capitation_contract_request, %{issue_city: "Львів"})

      insert(:il, :capitation_contract_request, %{
        issue_city: "Київ",
        contractor_legal_entity_id: legal_entity_id_1,
        contract_number: contract_number
      })

      insert(:il, :capitation_contract_request, %{
        issue_city: "Київ",
        contractor_legal_entity_id: legal_entity_id_1,
        nhs_signer_id: nhs_signer_id
      })

      insert(:il, :capitation_contract_request, %{
        issue_city: "Львів",
        contractor_legal_entity_id: legal_entity_id_1,
        status: CapitationContractRequest.status(:declined)
      })

      insert(:il, :capitation_contract_request, %{
        issue_city: "Київ",
        contractor_legal_entity_id: legal_entity_id_2,
        contractor_owner_id: contractor_owner_id
      })

      insert(:il, :capitation_contract_request, %{
        issue_city: "Львів",
        nhs_signer_id: nhs_signer_id,
        status: CapitationContractRequest.status(:signed)
      })

      {:ok,
       %{
         nhs_signer_id: nhs_signer_id,
         contract_number: contract_number,
         contractor_owner_id: contractor_owner_id,
         legal_entity_id_1: legal_entity_id_1,
         legal_entity_id_2: legal_entity_id_2
       }}
    end

    test "finds by status as MSP", %{
      conn: conn,
      legal_entity_id_1: legal_entity_id
    } do
      msp(2)

      %{"data" => response_data} = do_get_contract_request(conn, legal_entity_id, %{"status" => "New"})

      assert [%{"status" => @contract_request_status_new}, _] = response_data

      %{"data" => response_data} =
        do_get_contract_request(conn, legal_entity_id, %{
          "issue_city" => "ЛЬВІВ",
          "status" => "declined"
        })

      assert [%{"status" => @contract_request_status_declined}] = response_data
    end

    test "find by status as NHS", %{
      conn: conn,
      legal_entity_id_2: legal_entity_id
    } do
      nhs()

      %{"data" => response_data} = do_get_contract_request(conn, legal_entity_id, %{"status" => "new"})

      assert 4 === length(response_data)
    end

    test "finds by issue city", %{conn: conn, legal_entity_id_1: legal_entity_id_1} do
      msp()

      %{"data" => response_data} = do_get_contract_request(conn, legal_entity_id_1, %{"issue_city" => "КИЇВ"})

      assert 2 === length(response_data)
    end

    test "finds by attributtes as MSP", %{
      conn: conn,
      contract_number: contract_number,
      legal_entity_id_1: legal_entity_id
    } do
      msp(2)

      %{"data" => response_data} =
        do_get_contract_request(conn, legal_entity_id, %{"contract_number" => contract_number})

      assert [%{"contract_number" => ^contract_number}] = response_data

      %{"data" => response_data} =
        do_get_contract_request(conn, legal_entity_id, %{
          "contractor_legal_entity_id" => legal_entity_id
        })

      assert [%{"contractor_legal_entity_id" => ^legal_entity_id}, _, _] = response_data
    end

    test "finds by attributtes as NHS", %{
      conn: conn,
      contractor_owner_id: contractor_owner_id,
      nhs_signer_id: nhs_signer_id,
      legal_entity_id_2: legal_entity_id
    } do
      nhs(2)

      %{"data" => response_data} =
        do_get_contract_request(conn, legal_entity_id, %{
          "contractor_owner_id" => contractor_owner_id
        })

      assert [%{"contractor_owner_id" => ^contractor_owner_id}] = response_data

      %{"data" => response_data} = do_get_contract_request(conn, legal_entity_id, %{"nhs_signer_id" => nhs_signer_id})

      assert [%{"nhs_signer_id" => ^nhs_signer_id}, _] = response_data
    end

    test "finds nothing", %{conn: conn, legal_entity_id_1: legal_entity_id_1} do
      msp()

      assert %{"data" => []} =
               do_get_contract_request(conn, legal_entity_id_1, %{
                 "contract_number" => UUID.generate()
               })
    end
  end

  defp do_get_contract_request(conn, client_id, search_params) do
    conn =
      conn
      |> put_client_id_header(client_id)
      |> get(contract_request_path(conn, :index, @capitation), search_params)

    json_response(conn, 200)
  end

  describe "sign nhs" do
    test "no contract_request found", %{conn: conn} do
      nhs()

      assert conn
             |> put_client_id_header(UUID.generate())
             |> patch(contract_request_path(conn, :sign_nhs, @capitation, UUID.generate()))
             |> json_response(404)
    end

    test "invalid client_id", %{conn: conn} do
      nhs()
      contract_request = insert(:il, :capitation_contract_request)
      legal_entity = insert(:prm, :legal_entity)
      nhs_signer_party = insert(:prm, :party)

      data = %{"id" => contract_request.id, "printout_content" => "<html></html>"}

      expect_signed_content(data, [
        %{
          edrpou: legal_entity.edrpou,
          drfo: nhs_signer_party.tax_id,
          surname: nhs_signer_party.last_name
        },
        %{
          edrpou: legal_entity.edrpou,
          drfo: nhs_signer_party.tax_id,
          surname: nhs_signer_party.last_name,
          is_stamp: true
        }
      ])

      assert resp =
               conn
               |> put_client_id_header(legal_entity.id)
               |> patch(contract_request_path(conn, :sign_nhs, @capitation, contract_request.id), %{
                 "signed_content" => "",
                 "signed_content_encoding" => "base64"
               })
               |> json_response(403)

      assert %{"message" => "Invalid client_id", "type" => "forbidden"} = resp["error"]
    end

    test "invalid user drfo in DS", %{conn: conn} do
      nhs()
      id = UUID.generate()

      data = %{
        "id" => id,
        "contract_number" => "0000-9EAX-XT7X-3115",
        "status" => CapitationContractRequest.status(:pending_nhs_sign)
      }

      %{
        "user_id" => user_id,
        "contract_request" => contract_request,
        "legal_entity" => legal_entity,
        "nhs_signer" => nhs_signer
      } =
        prepare_nhs_sign_params(
          id: id,
          data: data,
          status: CapitationContractRequest.status(:pending_nhs_sign)
        )

      data = Map.put(data, "printout_content", "<html></html>")
      client_id = nhs_signer.legal_entity.id

      expect_signed_content(data, [
        %{
          edrpou: nhs_signer.legal_entity.edrpou,
          drfo: "test",
          surname: nhs_signer.party.last_name
        },
        %{
          edrpou: nhs_signer.legal_entity.edrpou,
          drfo: "test",
          surname: nhs_signer.party.last_name,
          is_stamp: true
        }
      ])

      assert resp =
               conn
               |> put_client_id_header(client_id)
               |> put_consumer_id_header(user_id)
               |> put_req_header("drfo", legal_entity.edrpou)
               |> patch(contract_request_path(conn, :sign_nhs, @capitation, contract_request.id), %{
                 "signed_content" => "",
                 "signed_content_encoding" => "base64"
               })
               |> json_response(422)

      assert %{
               "invalid" => [
                 %{
                   "entry" => "$.drfo",
                   "entry_type" => "json_data_property",
                   "rules" => [
                     %{
                       "description" => "Does not match the signer drfo",
                       "params" => [],
                       "rule" => "invalid"
                     }
                   ]
                 }
               ]
             } = resp["error"]
    end

    test "invalid contract_request id from signed content", %{conn: conn} do
      nhs()
      legal_entity = insert(:prm, :legal_entity)
      contract_request = insert(:il, :capitation_contract_request)
      nhs_signer_party = insert(:prm, :party)

      data = %{"id" => contract_request.id, "printout_content" => "<html></html>"}

      drfo_signed_content(data, [
        %{drfo: legal_entity.edrpou, surname: nhs_signer_party.last_name},
        %{drfo: legal_entity.edrpou, surname: nhs_signer_party.last_name, is_stamp: true}
      ])

      assert resp =
               conn
               |> put_client_id_header(legal_entity.id)
               |> patch(contract_request_path(conn, :sign_nhs, @capitation, UUID.generate()), %{
                 "signed_content" => "",
                 "signed_content_encoding" => "base64"
               })
               |> json_response(400)

      assert %{"message" => _, "type" => "request_malformed"} = resp["error"]
    end

    test "contract_request already signed", %{conn: conn} do
      nhs()

      %{
        "user_id" => user_id,
        "legal_entity" => legal_entity,
        "nhs_signer" => nhs_signer,
        "contract_request" => contract_request
      } = prepare_nhs_sign_params(status: CapitationContractRequest.status(:nhs_signed))

      data = %{"id" => contract_request.id, "printout_content" => "<html></html>"}

      expect_signed_content(data, [
        %{
          edrpou: legal_entity.edrpou,
          drfo: nhs_signer.party.tax_id,
          surname: nhs_signer.party.last_name
        },
        %{
          edrpou: legal_entity.edrpou,
          drfo: nhs_signer.party.tax_id,
          surname: nhs_signer.party.last_name,
          is_stamp: true
        }
      ])

      client_id = nhs_signer.legal_entity.id

      assert resp =
               conn
               |> put_client_id_header(client_id)
               |> put_consumer_id_header(user_id)
               |> patch(contract_request_path(conn, :sign_nhs, @capitation, contract_request.id), %{
                 "signed_content" => "",
                 "signed_content_encoding" => "base64"
               })
               |> json_response(422)

      assert_error(resp, "The contract was already signed by NHS")
    end

    test "failed to decode signed content", %{conn: conn} do
      nhs()
      invalid_signed_content()

      %{
        "client_id" => client_id,
        "user_id" => user_id,
        "contract_request" => contract_request
      } = prepare_nhs_sign_params(status: CapitationContractRequest.status(:pending_nhs_sign))

      conn =
        conn
        |> put_client_id_header(client_id)
        |> put_consumer_id_header(user_id)

      assert resp =
               conn
               |> patch(contract_request_path(conn, :sign_nhs, @capitation, contract_request.id), %{
                 "signed_content" => "invalid",
                 "signed_content_encoding" => "base64"
               })
               |> json_response(422)

      %{"error" => %{"invalid" => [%{"rules" => [%{"description" => "Not a base64 string"}]}]}} = resp
    end

    test "content doesn't match", %{conn: conn} do
      insert(:il, :dictionary, name: "POSITION", values: %{})
      insert(:il, :dictionary, name: "SETTLEMENT_TYPE", values: %{})
      insert(:il, :dictionary, name: "STREET_TYPE", values: %{})
      insert(:il, :dictionary, name: "SPECIALITY_TYPE", values: %{})
      insert(:il, :dictionary, name: "MEDICAL_SERVICE", values: %{})
      nhs()
      template()

      %{
        "user_id" => user_id,
        "contract_request" => contract_request,
        "legal_entity" => legal_entity,
        "nhs_signer" => nhs_signer
      } = prepare_nhs_sign_params(status: CapitationContractRequest.status(:pending_nhs_sign))

      client_id = nhs_signer.legal_entity.id

      data = %{"id" => contract_request.id, "printout_content" => "<html></html>"}

      expect_signed_content(data, [
        %{
          edrpou: nhs_signer.legal_entity.edrpou,
          drfo: nhs_signer.party.tax_id,
          surname: nhs_signer.party.last_name
        },
        %{
          edrpou: nhs_signer.legal_entity.edrpou,
          drfo: nhs_signer.party.tax_id,
          surname: nhs_signer.party.last_name,
          is_stamp: true
        }
      ])

      resp =
        conn
        |> put_client_id_header(client_id)
        |> put_consumer_id_header(user_id)
        |> put_req_header("drfo", legal_entity.edrpou)
        |> patch(contract_request_path(conn, :sign_nhs, @capitation, contract_request.id), %{
          "signed_content" => data |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(422)

      assert_error(resp, "Signed content does not match the previously created content")
    end

    test "stamp is required", %{conn: conn} do
      insert(:il, :dictionary, name: "SETTLEMENT_TYPE", values: %{})
      insert(:il, :dictionary, name: "STREET_TYPE", values: %{})
      insert(:il, :dictionary, name: "SPECIALITY_TYPE", values: %{})
      insert(:il, :dictionary, name: "MEDICAL_SERVICE", values: %{})
      nhs()
      template()

      expect(MediaStorageMock, :store_signed_content, fn _, _, _, _ ->
        {:ok, "success"}
      end)

      id = UUID.generate()

      data = %{
        "id" => id,
        "contract_number" => "0000-9EAX-XT7X-3115",
        "status" => CapitationContractRequest.status(:pending_nhs_sign)
      }

      %{
        "client_id" => client_id,
        "user_id" => user_id,
        "contract_request" => contract_request,
        "legal_entity" => legal_entity,
        "party_user" => party_user
      } =
        prepare_nhs_sign_params(
          id: id,
          data: data,
          status: CapitationContractRequest.status(:pending_nhs_sign)
        )

      data = Map.put(data, "printout_content", "<html></html>")

      drfo_signed_content(data, [
        %{drfo: legal_entity.edrpou, surname: party_user.party.last_name}
      ])

      resp =
        conn
        |> put_client_id_header(client_id)
        |> put_consumer_id_header(user_id)
        |> put_req_header("drfo", legal_entity.edrpou)
        |> patch(contract_request_path(conn, :sign_nhs, @capitation, contract_request.id), %{
          "signed_content" => data |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(400)

      assert %{
               "invalid" => [
                 %{"entry_type" => "request", "rules" => [%{"rule" => "json"}]}
               ],
               "message" => "document must contain 1 signature and 1 stamp but contains 1 signature and 0 stamps",
               "type" => "request_malformed"
             } = resp["error"]
    end

    test "legal entity edrpou does not match with signer edrpou", %{conn: conn} do
      insert(:il, :dictionary, name: "SETTLEMENT_TYPE", values: %{})
      insert(:il, :dictionary, name: "STREET_TYPE", values: %{})
      insert(:il, :dictionary, name: "SPECIALITY_TYPE", values: %{})
      insert(:il, :dictionary, name: "MEDICAL_SERVICE", values: %{})
      nhs()
      template()

      expect(MediaStorageMock, :store_signed_content, fn _, _, _, _ ->
        {:ok, "success"}
      end)

      id = UUID.generate()

      data = %{
        "id" => id,
        "contract_number" => "0000-9EAX-XT7X-3115",
        "status" => CapitationContractRequest.status(:pending_nhs_sign)
      }

      %{
        "user_id" => user_id,
        "contract_request" => contract_request,
        "legal_entity" => legal_entity,
        "nhs_signer" => nhs_signer
      } =
        prepare_nhs_sign_params(
          id: id,
          data: data,
          status: CapitationContractRequest.status(:pending_nhs_sign)
        )

      data = Map.put(data, "printout_content", "<html></html>")

      expect_signed_content(data, [
        %{
          edrpou: nhs_signer.party.tax_id,
          drfo: nhs_signer.party.tax_id,
          surname: nhs_signer.party.last_name
        },
        %{
          edrpou: legal_entity.edrpou,
          drfo: nhs_signer.party.tax_id,
          surname: nhs_signer.party.last_name,
          is_stamp: true
        }
      ])

      client_id = nhs_signer.legal_entity.id

      resp =
        conn
        |> put_client_id_header(client_id)
        |> put_consumer_id_header(user_id)
        |> put_req_header("drfo", nhs_signer.legal_entity.edrpou)
        |> patch(contract_request_path(conn, :sign_nhs, @capitation, contract_request.id), %{
          "signed_content" => data |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(422)

      assert %{
               "invalid" => [
                 %{
                   "entry" => "$.edrpou"
                 }
               ]
             } = resp["error"]
    end

    test "legal entity edrpou does not match with stamp edrpou", %{conn: conn} do
      insert(:il, :dictionary, name: "SETTLEMENT_TYPE", values: %{})
      insert(:il, :dictionary, name: "STREET_TYPE", values: %{})
      insert(:il, :dictionary, name: "SPECIALITY_TYPE", values: %{})
      insert(:il, :dictionary, name: "MEDICAL_SERVICE", values: %{})
      nhs()
      template()

      expect(MediaStorageMock, :store_signed_content, fn _, _, _, _ ->
        {:ok, "success"}
      end)

      id = UUID.generate()

      data = %{
        "id" => id,
        "contract_number" => "0000-9EAX-XT7X-3115",
        "status" => CapitationContractRequest.status(:pending_nhs_sign)
      }

      %{
        "user_id" => user_id,
        "contract_request" => contract_request,
        "legal_entity" => legal_entity,
        "party_user" => party_user,
        "nhs_signer" => nhs_signer
      } =
        prepare_nhs_sign_params(
          id: id,
          data: data,
          status: CapitationContractRequest.status(:pending_nhs_sign)
        )

      data = Map.put(data, "printout_content", "<html></html>")

      expect_signed_content(data, [
        %{
          edrpou: legal_entity.edrpou,
          drfo: party_user.party.tax_id,
          surname: party_user.party.last_name
        },
        %{
          edrpou: party_user.party.tax_id,
          drfo: party_user.party.tax_id,
          surname: party_user.party.last_name,
          is_stamp: true
        }
      ])

      client_id = nhs_signer.legal_entity.id

      resp =
        conn
        |> put_client_id_header(client_id)
        |> put_consumer_id_header(user_id)
        |> put_req_header("drfo", legal_entity.edrpou)
        |> patch(contract_request_path(conn, :sign_nhs, @capitation, contract_request.id), %{
          "signed_content" => data |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(422)

      assert %{
               "invalid" => [
                 %{
                   "entry" => "$.edrpou"
                 }
               ]
             } = resp["error"]
    end

    test "party last_name does not match with signer surname", %{conn: conn} do
      insert(:il, :dictionary, name: "SETTLEMENT_TYPE", values: %{})
      insert(:il, :dictionary, name: "STREET_TYPE", values: %{})
      insert(:il, :dictionary, name: "SPECIALITY_TYPE", values: %{})
      insert(:il, :dictionary, name: "MEDICAL_SERVICE", values: %{})
      nhs()
      template()

      expect(MediaStorageMock, :store_signed_content, fn _, _, _, _ ->
        {:ok, "success"}
      end)

      id = UUID.generate()

      data = %{
        "id" => id,
        "contract_number" => "0000-9EAX-XT7X-3115",
        "status" => CapitationContractRequest.status(:pending_nhs_sign)
      }

      %{
        "user_id" => user_id,
        "contract_request" => contract_request,
        "legal_entity" => legal_entity,
        "nhs_signer" => nhs_signer
      } =
        prepare_nhs_sign_params(
          id: id,
          data: data,
          status: CapitationContractRequest.status(:pending_nhs_sign)
        )

      data = Map.put(data, "printout_content", "<html></html>")

      expect_signed_content(data, [
        %{
          edrpou: nhs_signer.legal_entity.edrpou,
          drfo: nhs_signer.party.tax_id,
          surname: "Підписант"
        },
        %{
          edrpou: nhs_signer.legal_entity.edrpou,
          drfo: nhs_signer.party.tax_id,
          surname: "Підписант",
          is_stamp: true
        }
      ])

      client_id = nhs_signer.legal_entity.id

      resp =
        conn
        |> put_client_id_header(client_id)
        |> put_consumer_id_header(user_id)
        |> put_req_header("drfo", legal_entity.edrpou)
        |> patch(contract_request_path(conn, :sign_nhs, @capitation, contract_request.id), %{
          "signed_content" => data |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(422)

      assert %{
               "invalid" => [
                 %{
                   "entry" => "$.last_name",
                   "rules" => [
                     %{
                       "description" => "Signer surname does not match with current user last_name",
                       "rule" => "invalid"
                     }
                   ]
                 }
               ]
             } = resp["error"]
    end

    test "invalid status", %{conn: conn} do
      id = UUID.generate()

      data = %{
        "id" => id,
        "printout_content" => "<html></html>",
        "contract_number" => "0000-9EAX-XT7X-3115"
      }

      nhs()

      %{
        "party_user" => party_user,
        "user_id" => user_id,
        "nhs_signer" => nhs_signer,
        "contract_request" => contract_request
      } = prepare_nhs_sign_params(id: id, data: data)

      expect_signed_content(data, [
        %{
          edrpou: nhs_signer.legal_entity.edrpou,
          drfo: nhs_signer.party.tax_id,
          surname: nhs_signer.party.tax_id
        },
        %{
          edrpou: nhs_signer.legal_entity.edrpou,
          drfo: nhs_signer.party.tax_id,
          surname: nhs_signer.party.tax_id,
          is_stamp: true
        }
      ])

      client_id = nhs_signer.legal_entity.id

      assert resp =
               conn
               |> put_client_id_header(client_id)
               |> put_consumer_id_header(user_id)
               |> put_req_header("drfo", party_user.party.tax_id)
               |> patch(contract_request_path(conn, :sign_nhs, @capitation, contract_request.id), %{
                 "signed_content" => data |> Jason.encode!() |> Base.encode64(),
                 "signed_content_encoding" => "base64"
               })
               |> json_response(409)

      assert %{
               "message" => "Incorrect status of contract_request to modify it",
               "type" => "request_conflict"
             } = resp["error"]
    end

    test "failed to save signed content", %{conn: conn} do
      insert(:il, :dictionary, name: "POSITION", values: %{})
      insert(:il, :dictionary, name: "SETTLEMENT_TYPE", values: %{})
      insert(:il, :dictionary, name: "STREET_TYPE", values: %{})
      insert(:il, :dictionary, name: "SPECIALITY_TYPE", values: %{})
      insert(:il, :dictionary, name: "MEDICAL_SERVICE", values: %{})
      nhs()

      expect(MediaStorageMock, :store_signed_content, fn _, _, _, _ ->
        {:error, "failed to save content"}
      end)

      template()
      id = UUID.generate()

      data = %{
        "id" => id,
        "printout_content" => "<html></html>",
        "contract_number" => "0000-9EAX-XT7X-3115",
        "status" => CapitationContractRequest.status(:pending_nhs_sign)
      }

      %{
        "user_id" => user_id,
        "party_user" => party_user,
        "legal_entity" => legal_entity,
        "contract_request" => contract_request,
        "nhs_signer" => nhs_signer
      } =
        prepare_nhs_sign_params(
          id: id,
          data: data,
          status: CapitationContractRequest.status(:pending_nhs_sign)
        )

      client_id = nhs_signer.legal_entity.id

      expect_signed_content(data, [
        %{
          edrpou: nhs_signer.legal_entity.edrpou,
          drfo: party_user.party.tax_id,
          surname: party_user.party.last_name
        },
        %{
          edrpou: nhs_signer.legal_entity.edrpou,
          drfo: party_user.party.tax_id,
          surname: party_user.party.last_name,
          is_stamp: true
        }
      ])

      assert resp =
               conn
               |> put_client_id_header(client_id)
               |> put_consumer_id_header(user_id)
               |> put_req_header("drfo", legal_entity.edrpou)
               |> patch(contract_request_path(conn, :sign_nhs, @capitation, contract_request.id), %{
                 "signed_content" => data |> Jason.encode!() |> Base.encode64(),
                 "signed_content_encoding" => "base64"
               })
               |> json_response(502)

      assert "Failed to save signed content" == resp["error"]["message"]
    end

    test "success to sign contract_request", %{conn: conn} do
      insert(:il, :dictionary, name: "POSITION", values: %{})
      insert(:il, :dictionary, name: "SETTLEMENT_TYPE", values: %{})
      insert(:il, :dictionary, name: "STREET_TYPE", values: %{})
      insert(:il, :dictionary, name: "SPECIALITY_TYPE", values: %{})
      insert(:il, :dictionary, name: "MEDICAL_SERVICE", values: %{})
      nhs()
      template()

      expect(MediaStorageMock, :store_signed_content, fn _, _, _, _ ->
        {:ok, "success"}
      end)

      expect(KafkaMock, :publish_to_event_manager, fn _ -> :ok end)

      id = UUID.generate()

      data = %{
        "id" => id,
        "contract_number" => "0000-9EAX-XT7X-3115",
        "status" => CapitationContractRequest.status(:pending_nhs_sign)
      }

      %{
        "user_id" => user_id,
        "contract_request" => contract_request,
        "legal_entity" => legal_entity,
        "nhs_signer" => nhs_signer
      } =
        prepare_nhs_sign_params(
          id: id,
          data: data,
          status: CapitationContractRequest.status(:pending_nhs_sign)
        )

      data = Map.put(data, "printout_content", "<html></html>")
      client_id = nhs_signer.legal_entity.id

      expect_signed_content(data, [
        %{
          edrpou: nhs_signer.legal_entity.edrpou,
          drfo: nhs_signer.party.tax_id,
          surname: nhs_signer.party.last_name
        },
        %{
          edrpou: nhs_signer.legal_entity.edrpou,
          drfo: nhs_signer.party.tax_id,
          surname: nhs_signer.party.last_name,
          is_stamp: true
        }
      ])

      contract_request = Core.Repo.get(CapitationContractRequest, contract_request.id)
      assert contract_request.nhs_signed_date == Date.utc_today()

      conn
      |> put_client_id_header(client_id)
      |> put_consumer_id_header(user_id)
      |> put_req_header("drfo", legal_entity.edrpou)
      |> patch(contract_request_path(conn, :sign_nhs, @capitation, contract_request.id), %{
        "signed_content" => data |> Jason.encode!() |> Base.encode64(),
        "signed_content_encoding" => "base64"
      })
      |> json_response(200)
      |> Map.get("data")
      |> assert_show_response_schema("contract_request/capitation", "contract_request")
    end
  end

  describe "decline contract_request" do
    setup %{conn: conn} do
      expect(MediaStorageMock, :store_signed_content, fn _, _, _, _ ->
        {:ok, "success"}
      end)

      user_id = UUID.generate()
      party_user = insert(:prm, :party_user, user_id: user_id)
      legal_entity = insert(:prm, :legal_entity)

      employee_owner =
        insert(
          :prm,
          :employee,
          legal_entity_id: legal_entity.id,
          employee_type: Employee.type(:owner),
          party: party_user.party
        )

      division = insert(:prm, :division, legal_entity: legal_entity)

      employee_doctor = insert(:prm, :employee, legal_entity_id: legal_entity.id, division: division)

      contract_request =
        insert(
          :il,
          :capitation_contract_request,
          status: @contract_request_status_in_process,
          nhs_signer_id: employee_owner.id,
          contractor_legal_entity_id: legal_entity.id,
          contractor_owner_id: employee_owner.id,
          contractor_employee_divisions: [
            %{
              "employee_id" => employee_doctor.id,
              "staff_units" => 0.5,
              "declaration_limit" => 2000,
              "division_id" => division.id
            }
          ]
        )

      {:ok,
       %{
         conn: conn,
         contract_request: contract_request,
         legal_entity: legal_entity,
         user_id: user_id,
         employee_owner: employee_owner,
         party_user: party_user
       }}
    end

    test "success decline contract request and event manager registration", context do
      %{
        conn: conn,
        contract_request: contract_request,
        legal_entity: legal_entity,
        user_id: user_id,
        party_user: party_user
      } = context

      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      expect(KafkaMock, :publish_to_event_manager, fn _ -> :ok end)

      data = %{
        "id" => contract_request.id,
        "next_status" => "DECLINED",
        "contractor_legal_entity" => %{
          "id" => contract_request.contractor_legal_entity_id,
          "name" => legal_entity.name,
          "edrpou" => legal_entity.edrpou
        },
        "status_reason" => "Не відповідає попереднім домовленостям",
        "text" => "something"
      }

      expect_signed_content(data, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: party_user.party.last_name
      })

      resp =
        conn
        |> put_client_id_header(legal_entity.id)
        |> put_consumer_id_header(user_id)
        |> put_req_header("drfo", legal_entity.edrpou)
        |> patch(contract_request_path(conn, :decline, @capitation, contract_request.id), %{
          "signed_content" => data |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(200)
        |> Map.get("data")
        |> assert_show_response_schema("contract_request/capitation", "contract_request")

      assert resp["status"] == CapitationContractRequest.status(:declined)

      contract_request = Core.Repo.get(CapitationContractRequest, contract_request.id)
      assert contract_request.status_reason == "Не відповідає попереднім домовленостям"
      assert contract_request.nhs_signer_id == user_id
      assert contract_request.nhs_legal_entity_id == legal_entity.id
    end

    test "legal entity edrpou does not match with signer drfo", context do
      %{
        conn: conn,
        contract_request: contract_request,
        legal_entity: legal_entity,
        user_id: user_id,
        party_user: party_user
      } = context

      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      data = %{
        "id" => contract_request.id,
        "next_status" => "DECLINED",
        "contractor_legal_entity" => %{
          "id" => contract_request.contractor_legal_entity_id,
          "name" => legal_entity.name,
          "edrpou" => legal_entity.edrpou
        },
        "status_reason" => "Не відповідає попереднім домовленостям",
        "text" => "something"
      }

      drfo_signed_content(data, party_user.party.tax_id, party_user.party.last_name)

      resp =
        conn
        |> put_client_id_header(legal_entity.id)
        |> put_consumer_id_header(user_id)
        |> put_req_header("drfo", party_user.party.tax_id)
        |> patch(contract_request_path(conn, :decline, @capitation, contract_request.id), %{
          "signed_content" => data |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(422)

      assert %{
               "invalid" => [
                 %{
                   "entry" => "$.drfo"
                 }
               ]
             } = resp["error"]
    end

    test "user last name does not match with signer surname", context do
      %{
        conn: conn,
        contract_request: contract_request,
        legal_entity: legal_entity,
        user_id: user_id,
        party_user: party_user
      } = context

      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      content = %{
        "id" => contract_request.id,
        "next_status" => "DECLINED",
        "contractor_legal_entity" => %{
          "id" => contract_request.contractor_legal_entity_id,
          "name" => legal_entity.name,
          "edrpou" => legal_entity.edrpou
        },
        "status_reason" => "Не відповідає попереднім домовленостям",
        "text" => "something"
      }

      expect_signed_content(content, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: "Підписант"
      })

      resp =
        conn
        |> put_client_id_header(legal_entity.id)
        |> put_consumer_id_header(user_id)
        |> put_req_header("drfo", party_user.party.tax_id)
        |> patch(contract_request_path(conn, :decline, @capitation, contract_request.id), %{
          "signed_content" => content |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(422)

      assert %{
               "invalid" => [
                 %{
                   "entry" => "$.last_name",
                   "rules" => [
                     %{
                       "description" => "Signer surname does not match with current user last_name"
                     }
                   ]
                 }
               ]
             } = resp["error"]
    end

    test "user is not NHS ADMIN SIGNER", context do
      %{
        conn: conn,
        contract_request: contract_request,
        legal_entity: legal_entity,
        user_id: user_id,
        party_user: party_user
      } = context

      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "OWNER"}]}}
      end)

      content = %{
        "id" => contract_request.id,
        "next_status" => "DECLINED",
        "contractor_legal_entity" => %{
          "id" => contract_request.contractor_legal_entity_id,
          "name" => legal_entity.name,
          "edrpou" => legal_entity.edrpou
        },
        "status_reason" => "Не відповідає попереднім домовленостям",
        "text" => "something"
      }

      expect_signed_content(content, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: party_user.party.last_name
      })

      conn
      |> put_client_id_header(legal_entity.id)
      |> put_consumer_id_header(user_id)
      |> put_req_header("drfo", party_user.party.tax_id)
      |> patch(contract_request_path(conn, :decline, @capitation, contract_request.id), %{
        "signed_content" => content |> Jason.encode!() |> Base.encode64(),
        "signed_content_encoding" => "base64"
      })
      |> json_response(403)
    end

    test "invalid user drfo in DS", context do
      %{
        conn: conn,
        contract_request: contract_request,
        legal_entity: legal_entity,
        user_id: user_id,
        party_user: party_user
      } = context

      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "OWNER"}]}}
      end)

      content = %{
        "id" => contract_request.id,
        "next_status" => "DECLINED",
        "contractor_legal_entity" => %{
          "id" => contract_request.contractor_legal_entity_id,
          "name" => legal_entity.name,
          "edrpou" => legal_entity.edrpou
        },
        "status_reason" => "Не відповідає попереднім домовленостям",
        "text" => "something"
      }

      expect_signed_content(content, %{
        edrpou: legal_entity.edrpou,
        drfo: "test",
        surname: party_user.party.last_name
      })

      resp =
        conn
        |> put_client_id_header(legal_entity.id)
        |> put_consumer_id_header(user_id)
        |> put_req_header("drfo", party_user.party.tax_id)
        |> patch(contract_request_path(conn, :decline, @capitation, contract_request.id), %{
          "signed_content" => content |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(422)

      assert %{
               "invalid" => [
                 %{"entry_type" => "request", "rules" => [%{"rule" => "json"}]}
               ],
               "message" => "Does not match the signer drfo",
               "type" => "request_malformed"
             } = resp["error"]
    end

    test "no contract_request found", context do
      %{
        conn: conn,
        legal_entity: legal_entity,
        user_id: user_id,
        party_user: party_user
      } = context

      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      contract_request_id = UUID.generate()

      content = %{
        "id" => contract_request_id,
        "next_status" => "DECLINED",
        "contractor_legal_entity" => %{
          "id" => legal_entity.id,
          "name" => legal_entity.name,
          "edrpou" => legal_entity.edrpou
        },
        "status_reason" => "Не відповідає попереднім домовленостям",
        "text" => "something"
      }

      expect_signed_content(content, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: party_user.party.last_name
      })

      conn
      |> put_client_id_header(legal_entity.id)
      |> put_consumer_id_header(user_id)
      |> patch(contract_request_path(conn, :decline, @capitation, contract_request_id), %{
        "signed_content" => content |> Jason.encode!() |> Base.encode64(),
        "signed_content_encoding" => "base64"
      })
      |> json_response(404)
    end

    test "contract_request has wrong status", context do
      %{
        conn: conn,
        legal_entity: legal_entity,
        user_id: user_id,
        employee_owner: employee_owner,
        party_user: party_user
      } = context

      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      contract_request =
        insert(
          :il,
          :capitation_contract_request,
          contractor_legal_entity_id: legal_entity.id,
          status: CapitationContractRequest.status(:signed),
          nhs_signer_id: employee_owner.id
        )

      data = %{
        "id" => contract_request.id,
        "next_status" => "DECLINED",
        "contractor_legal_entity" => %{
          "id" => contract_request.contractor_legal_entity_id,
          "name" => legal_entity.name,
          "edrpou" => legal_entity.edrpou
        },
        "status_reason" => "Не відповідає попереднім домовленостям",
        "text" => "something"
      }

      expect_signed_content(data, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: party_user.party.last_name
      })

      resp =
        conn
        |> put_client_id_header(legal_entity.id)
        |> put_consumer_id_header(user_id)
        |> put_req_header("drfo", legal_entity.edrpou)
        |> patch(contract_request_path(conn, :decline, @capitation, contract_request.id), %{
          "signed_content" => data |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(409)

      assert %{
               "message" => "Incorrect status of contract_request to modify it",
               "type" => "request_conflict"
             } = resp["error"]
    end

    test "status_reason is too long", context do
      %{
        conn: conn,
        legal_entity: legal_entity,
        user_id: user_id,
        employee_owner: employee_owner,
        party_user: party_user
      } = context

      expect(MithrilMock, :get_user_roles, fn _, _, _ ->
        {:ok, %{"data" => [%{"role_name" => "NHS ADMIN SIGNER"}]}}
      end)

      contract_request =
        insert(
          :il,
          :capitation_contract_request,
          contractor_legal_entity_id: legal_entity.id,
          status: CapitationContractRequest.status(:signed),
          nhs_signer_id: employee_owner.id
        )

      data = %{
        "id" => contract_request.id,
        "next_status" => "DECLINED",
        "contractor_legal_entity" => %{
          "id" => contract_request.contractor_legal_entity_id,
          "name" => legal_entity.name,
          "edrpou" => legal_entity.edrpou
        },
        "status_reason" => String.duplicate("a", 3001),
        "text" => "something"
      }

      expect_signed_content(data, %{
        edrpou: legal_entity.edrpou,
        drfo: party_user.party.tax_id,
        surname: party_user.party.last_name
      })

      resp =
        conn
        |> put_client_id_header(legal_entity.id)
        |> put_consumer_id_header(user_id)
        |> put_req_header("drfo", legal_entity.edrpou)
        |> patch(contract_request_path(conn, :decline, @capitation, contract_request.id), %{
          "signed_content" => data |> Jason.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(422)

      assert %{
               "invalid" => [
                 %{
                   "entry" => "$.status_reason",
                   "entry_type" => "json_data_property",
                   "rules" => [
                     %{
                       "description" => "expected value to have a maximum length of 3000 but was 3001",
                       "params" => %{"max" => 3000},
                       "rule" => "length"
                     }
                   ]
                 }
               ]
             } = resp["error"]
    end
  end

  describe "get partially signed capitation contract request url" do
    test "returns url successfully to owner", %{conn: conn} do
      msp()

      # TODO: swap parameters `resource_name` and `id`
      expect(MediaStorageMock, :create_signed_url, fn _, _, id, resource_name ->
        {:ok, %{secret_url: "http://url.com/#{id}/#{resource_name}"}}
      end)

      %{user_id: user_id, owner: employee} = prepare_data()
      client_id = employee.legal_entity_id

      contract_request =
        insert(
          :il,
          :capitation_contract_request,
          status: CapitationContractRequest.status(:nhs_signed),
          contractor_owner_id: employee.id,
          contractor_legal_entity_id: client_id
        )

      url_expected = "http://url.com/#{contract_request.id}/contract_request_content.pkcs7"

      assert %{"data" => %{"url" => ^url_expected}} =
               conn
               |> put_client_id_header(client_id)
               |> put_consumer_id_header(user_id)
               |> get(contract_request_path(conn, :get_partially_signed_content, @capitation, contract_request.id))
               |> json_response(200)
    end

    test "contract request was not signed by nhs", %{conn: conn} do
      msp()
      contract_request = insert(:il, :capitation_contract_request, status: CapitationContractRequest.status(:new))

      assert %{"error" => %{"message" => "The contract hasn't been signed yet"}} =
               conn
               |> put_client_id_header(UUID.generate())
               |> put_consumer_id_header(UUID.generate())
               |> get(contract_request_path(conn, :get_partially_signed_content, @capitation, contract_request.id))
               |> json_response(422)
    end

    test "invalid client id for contractor_legal_entity_id", %{conn: conn} do
      msp()

      contract_request =
        insert(:il, :capitation_contract_request, status: CapitationContractRequest.status(:nhs_signed))

      assert %{"error" => %{"type" => "forbidden", "message" => _}} =
               conn
               |> put_client_id_header(UUID.generate())
               |> put_consumer_id_header(UUID.generate())
               |> get(contract_request_path(conn, :get_partially_signed_content, @capitation, contract_request.id))
               |> json_response(403)
    end

    test "media storage fail to resolve url", %{conn: conn} do
      msp()

      expect(MediaStorageMock, :create_signed_url, fn _, _, _, _ ->
        {:ok, %{"error" => %{}}}
      end)

      %{user_id: user_id, owner: employee} = prepare_data()
      client_id = employee.legal_entity_id

      contract_request =
        insert(
          :il,
          :capitation_contract_request,
          status: CapitationContractRequest.status(:nhs_signed),
          contractor_owner_id: employee.id,
          contractor_legal_entity_id: client_id
        )

      assert %{"error" => _} =
               conn
               |> put_client_id_header(client_id)
               |> put_consumer_id_header(user_id)
               |> get(contract_request_path(conn, :get_partially_signed_content, @capitation, contract_request.id))
               |> json_response(502)
    end
  end

  describe "sign MSP" do
    test "no contract_request found", %{conn: conn} do
      msp()

      assert conn
             |> put_client_id_header(UUID.generate())
             |> patch(contract_request_path(conn, :sign_msp, @capitation, UUID.generate()))
             |> json_response(404)
    end

    test "invalid client_id", %{conn: conn} do
      nhs()

      contract_request =
        insert(:il, :capitation_contract_request, status: CapitationContractRequest.status(:nhs_signed))

      legal_entity = insert(:prm, :legal_entity)
      conn = put_client_id_header(conn, legal_entity.id)

      assert resp =
               conn
               |> patch(contract_request_path(conn, :sign_msp, @capitation, contract_request.id), %{
                 "signed_content" => "",
                 "signed_content_encoding" => "base64"
               })
               |> json_response(403)

      assert "Invalid client_id" == resp["error"]["message"]
    end

    test "contract_request already signed", %{conn: conn} do
      nhs()

      %{"client_id" => client_id, "user_id" => user_id, "contract_request" => contract_request} =
        prepare_nhs_sign_params(status: CapitationContractRequest.status(:signed))

      assert resp =
               conn
               |> put_client_id_header(client_id)
               |> put_consumer_id_header(user_id)
               |> patch(contract_request_path(conn, :sign_msp, @capitation, contract_request.id), %{
                 "signed_content" => "",
                 "signed_content_encoding" => "base64"
               })
               |> json_response(422)

      assert_error(resp, "Incorrect status for signing")
    end

    test "failed to decode signed content", %{conn: conn} do
      nhs()
      invalid_signed_content()

      %{
        "client_id" => client_id,
        "user_id" => user_id,
        "contract_request" => contract_request,
        "party_user" => party_user
      } = prepare_nhs_sign_params(status: CapitationContractRequest.status(:nhs_signed))

      assert resp =
               conn
               |> put_client_id_header(client_id)
               |> put_consumer_id_header(user_id)
               |> put_req_header("msp_drfo", party_user.party.tax_id)
               |> patch(contract_request_path(conn, :sign_msp, @capitation, contract_request.id), %{
                 "signed_content" => "invalid",
                 "signed_content_encoding" => "base64"
               })
               |> json_response(422)

      assert %{
               "invalid" => [
                 %{
                   "entry" => "$.signed_content",
                   "entry_type" => "json_data_property",
                   "rules" => [
                     %{
                       "description" => "Not a base64 string",
                       "params" => [],
                       "rule" => "invalid"
                     }
                   ]
                 }
               ],
               "type" => "validation_failed"
             } = resp["error"]
    end

    test "legal entity edrpou does not match with signer drfo", %{conn: conn} do
      insert(:il, :dictionary, name: "SETTLEMENT_TYPE", values: %{})
      insert(:il, :dictionary, name: "STREET_TYPE", values: %{})
      insert(:il, :dictionary, name: "SPECIALITY_TYPE", values: %{})
      nhs()
      template()

      %{
        "client_id" => client_id,
        "user_id" => user_id,
        "contract_request" => contract_request,
        "legal_entity" => legal_entity,
        "party_user" => party_user
      } = prepare_nhs_sign_params(status: CapitationContractRequest.status(:nhs_signed))

      conn =
        conn
        |> put_client_id_header(client_id)
        |> put_consumer_id_header(user_id)
        |> put_req_header("msp_drfo", legal_entity.edrpou)

      data = %{"id" => contract_request.id, "printout_content" => "<html></html>"}

      drfo_signed_content(data, [
        %{drfo: party_user.party.tax_id, surname: party_user.party.last_name},
        %{drfo: nil, surname: nil},
        %{drfo: legal_entity.edrpou, surname: party_user.party.last_name, is_stamp: true}
      ])

      resp =
        conn
        |> patch(contract_request_path(conn, :sign_msp, @capitation, contract_request.id), %{
          "signed_content" => data |> Poison.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(422)

      assert %{
               "invalid" => [
                 %{
                   "entry" => "$.drfo"
                 }
               ]
             } = resp["error"]
    end

    test "party last_name does not match with signer surname", %{conn: conn} do
      insert(:il, :dictionary, name: "SETTLEMENT_TYPE", values: %{})
      insert(:il, :dictionary, name: "STREET_TYPE", values: %{})
      insert(:il, :dictionary, name: "SPECIALITY_TYPE", values: %{})
      nhs()
      template()

      %{
        "client_id" => client_id,
        "user_id" => user_id,
        "contract_request" => contract_request,
        "legal_entity" => legal_entity,
        "nhs_signer" => nhs_signer
      } = prepare_nhs_sign_params(status: CapitationContractRequest.status(:nhs_signed))

      data = %{"id" => contract_request.id, "printout_content" => "<html></html>"}

      expect_signed_content(data, [
        %{
          edrpou: legal_entity.edrpou,
          drfo: nhs_signer.party.tax_id,
          surname: "Підписант"
        },
        %{
          edrpou: nhs_signer.legal_entity.edrpou,
          drfo: nhs_signer.legal_entity.edrpou,
          surname: nhs_signer.party.last_name
        },
        %{
          edrpou: legal_entity.edrpou,
          drfo: nhs_signer.party.tax_id,
          surname: "Підписант",
          is_stamp: true
        }
      ])

      assert resp =
               conn
               |> put_client_id_header(client_id)
               |> put_consumer_id_header(user_id)
               |> put_req_header("msp_drfo", legal_entity.edrpou)
               |> patch(contract_request_path(conn, :sign_msp, @capitation, contract_request.id), %{
                 "signed_content" => data |> Poison.encode!() |> Base.encode64(),
                 "signed_content_encoding" => "base64"
               })
               |> json_response(422)

      assert %{
               "invalid" => [
                 %{
                   "entry" => "$.last_name",
                   "rules" => [
                     %{
                       "description" => "Signer surname does not match with current user last_name"
                     }
                   ]
                 }
               ]
             } = resp["error"]
    end

    test "content doesn't match", %{conn: conn} do
      insert(:il, :dictionary, name: "SETTLEMENT_TYPE", values: %{})
      insert(:il, :dictionary, name: "STREET_TYPE", values: %{})
      insert(:il, :dictionary, name: "SPECIALITY_TYPE", values: %{})
      nhs()
      template()

      %{
        "client_id" => client_id,
        "user_id" => user_id,
        "contract_request" => contract_request,
        "legal_entity" => legal_entity,
        "contractor_owner_id" => employee_owner,
        "nhs_signer" => nhs_signer
      } = prepare_nhs_sign_params(status: CapitationContractRequest.status(:nhs_signed))

      data = %{"id" => contract_request.id, "printout_content" => "<html></html>"}

      expect_signed_content(data, [
        %{
          edrpou: legal_entity.edrpou,
          drfo: employee_owner.party.tax_id,
          surname: employee_owner.party.last_name
        },
        %{
          edrpou: nhs_signer.legal_entity.edrpou,
          drfo: nhs_signer.party.tax_id,
          surname: nhs_signer.party.last_name
        },
        %{
          edrpou: nhs_signer.legal_entity.edrpou,
          drfo: nhs_signer.party.tax_id,
          surname: nhs_signer.party.last_name,
          is_stamp: true
        }
      ])

      assert resp =
               conn
               |> put_client_id_header(client_id)
               |> put_consumer_id_header(user_id)
               |> put_req_header("msp_drfo", legal_entity.edrpou)
               |> patch(contract_request_path(conn, :sign_msp, @capitation, contract_request.id), %{
                 "signed_content" => data |> Poison.encode!() |> Base.encode64(),
                 "signed_content_encoding" => "base64"
               })
               |> json_response(422)

      assert_error(resp, "Signed content does not match the previously created content")
    end

    test "failed to save signed content", %{conn: conn} do
      nhs()

      expect(MediaStorageMock, :store_signed_content, fn _, _, _, _ ->
        {:error, "failed to save content"}
      end)

      id = UUID.generate()

      data = %{
        "id" => id,
        "printout_content" => nil,
        "status" => CapitationContractRequest.status(:nhs_signed)
      }

      %{
        "client_id" => client_id,
        "user_id" => user_id,
        "contract_request" => contract_request,
        "legal_entity" => legal_entity,
        "contractor_owner_id" => employee_owner,
        "nhs_signer" => nhs_signer
      } =
        prepare_nhs_sign_params(
          id: id,
          data: data,
          status: CapitationContractRequest.status(:nhs_signed)
        )

      expect_signed_content(data, [
        %{
          edrpou: legal_entity.edrpou,
          drfo: employee_owner.party.tax_id,
          surname: employee_owner.party.last_name
        },
        %{
          edrpou: nhs_signer.legal_entity.edrpou,
          drfo: nhs_signer.party.tax_id,
          surname: nhs_signer.party.last_name
        },
        %{
          edrpou: nhs_signer.legal_entity.edrpou,
          drfo: nhs_signer.party.tax_id,
          surname: nhs_signer.party.last_name,
          is_stamp: true
        }
      ])

      assert resp =
               conn
               |> put_client_id_header(client_id)
               |> put_consumer_id_header(user_id)
               |> put_req_header("msp_drfo", legal_entity.edrpou)
               |> patch(contract_request_path(conn, :sign_msp, @capitation, contract_request.id), %{
                 "signed_content" => data |> Poison.encode!() |> Base.encode64(),
                 "signed_content_encoding" => "base64"
               })
               |> json_response(502)

      assert "Failed to save signed content" == resp["error"]["message"]
    end

    test "failed to create contract", %{conn: conn} do
      nhs()

      expect(MediaStorageMock, :store_signed_content, fn _, _, _, _ ->
        {:ok, "success"}
      end)

      id = UUID.generate()

      data = %{
        "id" => id,
        "printout_content" => nil,
        "status" => CapitationContractRequest.status(:nhs_signed)
      }

      %{
        "client_id" => client_id,
        "user_id" => user_id,
        "contract_request" => contract_request,
        "legal_entity" => legal_entity,
        "contractor_owner_id" => employee_owner,
        "nhs_signer" => nhs_signer
      } =
        prepare_nhs_sign_params(
          id: id,
          data: data,
          status: CapitationContractRequest.status(:nhs_signed)
        )

      conn =
        conn
        |> put_client_id_header(client_id)
        |> put_consumer_id_header(user_id)
        |> put_req_header("msp_drfo", legal_entity.edrpou)

      expect_signed_content(data, [
        %{
          edrpou: legal_entity.edrpou,
          drfo: employee_owner.party.tax_id,
          surname: employee_owner.party.last_name
        },
        %{
          edrpou: nhs_signer.legal_entity.edrpou,
          drfo: nhs_signer.party.tax_id,
          surname: nhs_signer.party.last_name
        },
        %{
          edrpou: nhs_signer.legal_entity.edrpou,
          drfo: nhs_signer.party.tax_id,
          surname: nhs_signer.party.last_name,
          is_stamp: true
        }
      ])

      assert conn
             |> patch(contract_request_path(conn, :sign_msp, @capitation, contract_request.id), %{
               "signed_content" => data |> Poison.encode!() |> Base.encode64(),
               "signed_content_encoding" => "base64"
             })
             |> json_response(502)
    end

    test "nhs_legal_entity does not exists", %{conn: conn} do
      nhs()
      template()

      expect(MediaStorageMock, :store_signed_content, fn _, _, _, _ ->
        {:ok, "success"}
      end)

      id = UUID.generate()

      data = %{
        "id" => id,
        "printout_content" => nil,
        "status" => CapitationContractRequest.status(:nhs_signed)
      }

      client_id = UUID.generate()
      legal_entity = insert(:prm, :legal_entity, id: client_id)

      nhs_signer = insert(:prm, :employee)

      user_id = UUID.generate()

      division =
        insert(
          :prm,
          :division,
          legal_entity: legal_entity,
          phones: [%{"type" => "MOBILE", "number" => "+380631111111"}]
        )

      employee_doctor = insert(:prm, :employee, legal_entity_id: legal_entity.id, division: division)

      employee_owner =
        insert(
          :prm,
          :employee,
          id: user_id,
          legal_entity_id: legal_entity.id,
          employee_type: Employee.type(:owner)
        )

      start_date = contract_start_date()

      params = %{
        id: id,
        data: data,
        status: CapitationContractRequest.status(:nhs_signed),
        contract_number: "1345",
        nhs_signed_date: Date.utc_today(),
        nhs_signer_id: nhs_signer.id,
        nhs_legal_entity_id: UUID.generate(),
        contractor_legal_entity_id: client_id,
        contractor_owner_id: employee_owner.id,
        contractor_divisions: [division.id],
        contractor_employee_divisions: [
          %{
            "employee_id" => employee_doctor.id,
            "staff_units" => 0.5,
            "declaration_limit" => 2000,
            "division_id" => division.id
          }
        ],
        start_date: start_date
      }

      contract_request = insert(:il, :capitation_contract_request, params)

      expect_signed_content(data, [
        %{
          edrpou: legal_entity.edrpou,
          drfo: employee_owner.party.tax_id,
          surname: employee_owner.party.last_name
        },
        %{
          edrpou: legal_entity.edrpou,
          drfo: nhs_signer.party.tax_id,
          surname: nhs_signer.party.last_name
        },
        %{
          edrpou: legal_entity.edrpou,
          drfo: nhs_signer.party.tax_id,
          surname: nhs_signer.party.last_name,
          is_stamp: true
        }
      ])

      resp =
        conn
        |> put_client_id_header(client_id)
        |> put_consumer_id_header(user_id)
        |> put_req_header("msp_drfo", legal_entity.edrpou)
        |> patch(contract_request_path(conn, :sign_msp, @capitation, contract_request.id), %{
          "signed_content" => data |> Poison.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(409)

      assert "NHS legal entity not found" == resp["error"]["message"]
    end

    test "nhs employee does not exists", %{conn: conn} do
      nhs()
      template()

      expect(MediaStorageMock, :store_signed_content, fn _, _, _, _ ->
        {:ok, "success"}
      end)

      id = UUID.generate()

      data = %{
        "id" => id,
        "printout_content" => nil,
        "status" => CapitationContractRequest.status(:nhs_signed)
      }

      client_id = UUID.generate()
      legal_entity = insert(:prm, :legal_entity, id: client_id)
      nhs_legal_entity = insert(:prm, :legal_entity)

      user_id = UUID.generate()

      division =
        insert(
          :prm,
          :division,
          legal_entity: legal_entity,
          phones: [%{"type" => "MOBILE", "number" => "+380631111111"}]
        )

      employee_doctor = insert(:prm, :employee, legal_entity_id: legal_entity.id, division: division)

      employee_owner =
        insert(
          :prm,
          :employee,
          id: user_id,
          legal_entity_id: legal_entity.id,
          employee_type: Employee.type(:owner)
        )

      start_date = contract_start_date()

      params = %{
        id: id,
        data: data,
        status: CapitationContractRequest.status(:nhs_signed),
        contract_number: "1345",
        nhs_signed_date: Date.utc_today(),
        nhs_signer_id: UUID.generate(),
        nhs_legal_entity_id: nhs_legal_entity.id,
        contractor_legal_entity_id: client_id,
        contractor_owner_id: employee_owner.id,
        contractor_divisions: [division.id],
        contractor_employee_divisions: [
          %{
            "employee_id" => employee_doctor.id,
            "staff_units" => 0.5,
            "declaration_limit" => 2000,
            "division_id" => division.id
          }
        ],
        start_date: start_date
      }

      contract_request = insert(:il, :capitation_contract_request, params)

      conn =
        conn
        |> put_client_id_header(client_id)
        |> put_consumer_id_header(user_id)
        |> put_req_header("msp_drfo", legal_entity.edrpou)

      expect_signed_content(data, [
        %{
          edrpou: legal_entity.edrpou,
          drfo: employee_owner.party.tax_id,
          surname: employee_owner.party.last_name
        },
        %{
          edrpou: legal_entity.edrpou,
          drfo: employee_owner.party.tax_id,
          surname: employee_owner.party.last_name
        },
        %{
          edrpou: legal_entity.edrpou,
          drfo: employee_owner.party.tax_id,
          surname: employee_owner.party.last_name,
          is_stamp: true
        }
      ])

      assert resp =
               conn
               |> patch(contract_request_path(conn, :sign_msp, @capitation, contract_request.id), %{
                 "signed_content" => data |> Poison.encode!() |> Base.encode64(),
                 "signed_content_encoding" => "base64"
               })
               |> json_response(409)

      assert "NHS employee not found" == resp["error"]["message"]
    end

    test "nhs signer edrpou does not match with nhs legal entity edrpou", %{conn: conn} do
      nhs()
      template()

      expect(MediaStorageMock, :store_signed_content, fn _, _, _, _ ->
        {:ok, "success"}
      end)

      id = UUID.generate()

      data = %{
        "id" => id,
        "printout_content" => nil,
        "status" => CapitationContractRequest.status(:nhs_signed)
      }

      %{
        "client_id" => client_id,
        "user_id" => user_id,
        "contract_request" => contract_request,
        "legal_entity" => legal_entity,
        "contractor_owner_id" => employee_owner,
        "nhs_signer" => nhs_signer
      } =
        prepare_nhs_sign_params(
          id: id,
          data: data,
          status: CapitationContractRequest.status(:nhs_signed),
          contract_number: "1345"
        )

      expect_signed_content(data, [
        %{
          edrpou: legal_entity.edrpou,
          drfo: legal_entity.edrpou,
          surname: employee_owner.party.last_name
        },
        %{
          edrpou: legal_entity.edrpou,
          drfo: legal_entity.edrpou,
          surname: nhs_signer.party.last_name
        },
        %{
          edrpou: legal_entity.edrpou,
          drfo: legal_entity.edrpou,
          surname: employee_owner.party.last_name,
          is_stamp: true
        }
      ])

      resp =
        conn
        |> put_client_id_header(client_id)
        |> put_consumer_id_header(user_id)
        |> put_req_header("msp_drfo", legal_entity.edrpou)
        |> patch(contract_request_path(conn, :sign_msp, @capitation, contract_request.id), %{
          "signed_content" => data |> Poison.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(422)

      assert [
               %{
                 "entry" => "$.drfo",
                 "rules" => [
                   %{
                     "description" => "Does not match the signer drfo"
                   }
                 ]
               }
             ] = resp["error"]["invalid"]
    end

    test "nhs signer surname does not match with nhs employee edrpou", %{conn: conn} do
      nhs()
      template()

      expect(MediaStorageMock, :store_signed_content, fn _, _, _, _ ->
        {:ok, "success"}
      end)

      id = UUID.generate()

      data = %{
        "id" => id,
        "printout_content" => nil,
        "status" => CapitationContractRequest.status(:nhs_signed)
      }

      %{
        "client_id" => client_id,
        "user_id" => user_id,
        "contract_request" => contract_request,
        "legal_entity" => legal_entity,
        "contractor_owner_id" => employee_owner,
        "nhs_signer" => nhs_signer
      } =
        prepare_nhs_sign_params(
          id: id,
          data: data,
          status: CapitationContractRequest.status(:nhs_signed),
          contract_number: "1345"
        )

      expect_signed_content(data, [
        %{
          edrpou: legal_entity.edrpou,
          drfo: employee_owner.party.tax_id,
          surname: employee_owner.party.last_name
        },
        %{
          edrpou: nhs_signer.legal_entity.edrpou,
          drfo: nhs_signer.party.tax_id,
          surname: "Чужий"
        },
        %{
          edrpou: nhs_signer.legal_entity.edrpou,
          drfo: nhs_signer.party.tax_id,
          surname: "Чужий",
          is_stamp: true
        }
      ])

      assert resp =
               conn
               |> put_client_id_header(client_id)
               |> put_consumer_id_header(user_id)
               |> put_req_header("msp_drfo", legal_entity.edrpou)
               |> patch(contract_request_path(conn, :sign_msp, @capitation, contract_request.id), %{
                 "signed_content" => data |> Poison.encode!() |> Base.encode64(),
                 "signed_content_encoding" => "base64"
               })
               |> json_response(422)

      assert [
               %{
                 "entry" => "$.last_name",
                 "entry_type" => "json_data_property",
                 "rules" => [
                   %{
                     "description" => "Signer surname does not match with current user last_name",
                     "params" => [],
                     "rule" => "invalid"
                   }
                 ]
               }
             ] == resp["error"]["invalid"]
    end

    test "stamp edrpou does not match nhs legal entity", %{conn: conn} do
      nhs()
      template()

      expect(MediaStorageMock, :store_signed_content, fn _, _, _, _ ->
        {:ok, "success"}
      end)

      id = UUID.generate()

      data = %{
        "id" => id,
        "printout_content" => nil,
        "status" => CapitationContractRequest.status(:nhs_signed)
      }

      %{
        "client_id" => client_id,
        "user_id" => user_id,
        "contract_request" => contract_request,
        "legal_entity" => legal_entity,
        "contractor_owner_id" => employee_owner,
        "nhs_signer" => nhs_signer
      } =
        prepare_nhs_sign_params(
          id: id,
          data: data,
          status: CapitationContractRequest.status(:nhs_signed),
          contract_number: "1345"
        )

      conn =
        conn
        |> put_client_id_header(client_id)
        |> put_consumer_id_header(user_id)
        |> put_req_header("msp_drfo", legal_entity.edrpou)

      expect_signed_content(data, [
        %{
          edrpou: legal_entity.edrpou,
          drfo: legal_entity.edrpou,
          surname: employee_owner.party.last_name
        },
        %{
          edrpou: legal_entity.edrpou,
          drfo: legal_entity.edrpou,
          surname: nhs_signer.party.last_name
        },
        %{
          edrpou: legal_entity.edrpou,
          drfo: legal_entity.edrpou,
          surname: employee_owner.party.last_name,
          is_stamp: true
        }
      ])

      assert resp =
               conn
               |> patch(contract_request_path(conn, :sign_msp, @capitation, contract_request.id), %{
                 "signed_content" => data |> Poison.encode!() |> Base.encode64(),
                 "signed_content_encoding" => "base64"
               })
               |> json_response(422)

      assert [
               %{
                 "entry" => "$.drfo",
                 "rules" => [
                   %{
                     "description" => "Does not match the signer drfo"
                   }
                 ]
               }
             ] = resp["error"]["invalid"]
    end

    test "success to sign contract_request", %{conn: conn} do
      nhs()
      template()

      expect(MediaStorageMock, :store_signed_content, fn _, bucket, _, _ ->
        assert :contract_bucket == bucket
        {:ok, "success"}
      end)

      expect(KafkaMock, :publish_to_event_manager, fn _ -> :ok end)

      id = UUID.generate()

      data = %{
        "id" => id,
        "printout_content" => nil,
        "status" => CapitationContractRequest.status(:nhs_signed)
      }

      %{
        "client_id" => client_id,
        "user_id" => user_id,
        "contract_request" => contract_request,
        "legal_entity" => legal_entity,
        "contractor_owner_id" => employee_owner,
        "nhs_signer" => nhs_signer
      } =
        prepare_nhs_sign_params(
          id: id,
          data: data,
          status: CapitationContractRequest.status(:nhs_signed),
          contract_number: "1345"
        )

      conn =
        conn
        |> put_client_id_header(client_id)
        |> put_consumer_id_header(user_id)
        |> put_req_header("msp_drfo", legal_entity.edrpou)

      expect_signed_content(data, [
        %{
          edrpou: legal_entity.edrpou,
          drfo: employee_owner.party.tax_id,
          surname: employee_owner.party.last_name
        },
        %{
          edrpou: nhs_signer.legal_entity.edrpou,
          drfo: nhs_signer.party.tax_id,
          surname: nhs_signer.party.last_name
        },
        %{
          edrpou: nhs_signer.legal_entity.edrpou,
          drfo: nhs_signer.party.tax_id,
          surname: nhs_signer.party.last_name,
          is_stamp: true
        }
      ])

      assert resp =
               conn
               |> patch(contract_request_path(conn, :sign_msp, @capitation, contract_request.id), %{
                 "signed_content" => data |> Poison.encode!() |> Base.encode64(),
                 "signed_content_encoding" => "base64"
               })
               |> json_response(200)

      schema =
        "../core/specs/json_schemas/contract/capitation_contract_show_response.json"
        |> File.read!()
        |> Poison.decode!()

      assert :ok = NExJsonSchema.Validator.validate(schema, resp["data"])
    end

    test "success to sign contract_request with existing parent_contract_id", %{conn: conn} do
      nhs()
      template()

      expect(MediaStorageMock, :store_signed_content, fn _, _, _, _ ->
        {:ok, "success"}
      end)

      expect(KafkaMock, :publish_to_event_manager, 2, fn _ -> :ok end)

      id = UUID.generate()

      data = %{
        "id" => id,
        "printout_content" => nil,
        "status" => CapitationContractRequest.status(:nhs_signed)
      }

      contract = insert(:prm, :capitation_contract, contract_number: "1345")
      employee = insert(:prm, :employee)
      insert(:prm, :contract_employee, contract_id: contract.id, employee_id: employee.id)
      insert(:prm, :contract_division, contract_id: contract.id)

      %{
        "client_id" => client_id,
        "user_id" => user_id,
        "legal_entity" => legal_entity,
        "contract_request" => contract_request,
        "contractor_owner_id" => employee_owner,
        "nhs_signer" => nhs_signer
      } =
        prepare_nhs_sign_params(
          id: id,
          data: data,
          status: CapitationContractRequest.status(:nhs_signed),
          contract_number: "1345",
          parent_contract_id: contract.id
        )

      expect_signed_content(data, [
        %{
          edrpou: legal_entity.edrpou,
          drfo: employee_owner.party.tax_id,
          surname: employee_owner.party.last_name
        },
        %{
          edrpou: nhs_signer.legal_entity.edrpou,
          drfo: nhs_signer.party.tax_id,
          surname: nhs_signer.party.last_name
        },
        %{
          edrpou: nhs_signer.legal_entity.edrpou,
          drfo: nhs_signer.party.tax_id,
          surname: nhs_signer.party.last_name,
          is_stamp: true
        }
      ])

      assert resp =
               conn
               |> put_client_id_header(client_id)
               |> put_consumer_id_header(user_id)
               |> put_req_header("msp_drfo", legal_entity.edrpou)
               |> patch(contract_request_path(conn, :sign_msp, @capitation, contract_request.id), %{
                 "signed_content" => data |> Poison.encode!() |> Base.encode64(),
                 "signed_content_encoding" => "base64"
               })
               |> json_response(200)

      schema =
        "../core/specs/json_schemas/contract/capitation_contract_show_response.json"
        |> File.read!()
        |> Poison.decode!()

      assert :ok = NExJsonSchema.Validator.validate(schema, resp["data"])
    end

    test "invalid user drfo in DS", %{conn: conn} do
      nhs()
      template()

      expect(MediaStorageMock, :store_signed_content, fn _, _, _, _ ->
        {:ok, "success"}
      end)

      id = UUID.generate()

      data = %{
        "id" => id,
        "printout_content" => nil,
        "status" => CapitationContractRequest.status(:nhs_signed)
      }

      contract = insert(:prm, :capitation_contract, contract_number: "1345")
      employee = insert(:prm, :employee)
      insert(:prm, :contract_employee, contract_id: contract.id, employee_id: employee.id)
      insert(:prm, :contract_division, contract_id: contract.id)

      %{
        "client_id" => client_id,
        "user_id" => user_id,
        "legal_entity" => legal_entity,
        "contract_request" => contract_request,
        "contractor_owner_id" => employee_owner,
        "nhs_signer" => nhs_signer
      } =
        prepare_nhs_sign_params(
          id: id,
          data: data,
          status: CapitationContractRequest.status(:nhs_signed),
          contract_number: "1345",
          parent_contract_id: contract.id
        )

      expect_signed_content(data, [
        %{
          edrpou: legal_entity.edrpou,
          drfo: "test",
          surname: employee_owner.party.last_name
        },
        %{
          edrpou: nhs_signer.legal_entity.edrpou,
          drfo: "test",
          surname: nhs_signer.party.last_name
        },
        %{
          edrpou: nhs_signer.legal_entity.edrpou,
          drfo: "test",
          surname: nhs_signer.party.last_name,
          is_stamp: true
        }
      ])

      resp =
        conn
        |> put_client_id_header(client_id)
        |> put_consumer_id_header(user_id)
        |> put_req_header("msp_drfo", legal_entity.edrpou)
        |> patch(contract_request_path(conn, :sign_msp, @capitation, contract_request.id), %{
          "signed_content" => data |> Poison.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(422)

      assert %{
               "invalid" => [
                 %{
                   "entry" => "$.drfo",
                   "entry_type" => "json_data_property",
                   "rules" => [
                     %{
                       "description" => "Does not match the signer drfo",
                       "params" => [],
                       "rule" => "invalid"
                     }
                   ]
                 }
               ]
             } = resp["error"]
    end

    test "fail to sign contract_request because of contract_number exist", %{conn: conn} do
      nhs()
      template()

      expect(MediaStorageMock, :store_signed_content, fn _, bucket, _, _ ->
        assert :contract_bucket == bucket
        {:ok, "success"}
      end)

      expect(KafkaMock, :publish_to_event_manager, fn _ -> :ok end)

      id = UUID.generate()

      data = %{
        "id" => id,
        "printout_content" => nil,
        "status" => CapitationContractRequest.status(:nhs_signed)
      }

      contract_number = generate_contract_number()
      insert(:prm, :capitation_contract, contract_number: contract_number, status: @contract_status_verified)

      %{
        "client_id" => client_id,
        "user_id" => user_id,
        "contract_request" => contract_request,
        "legal_entity" => legal_entity,
        "contractor_owner_id" => employee_owner,
        "nhs_signer" => nhs_signer
      } =
        prepare_nhs_sign_params(
          id: id,
          data: data,
          status: CapitationContractRequest.status(:nhs_signed),
          contract_number: contract_number
        )

      conn =
        conn
        |> put_client_id_header(client_id)
        |> put_consumer_id_header(user_id)
        |> put_req_header("msp_drfo", legal_entity.edrpou)

      expect_signed_content(data, [
        %{
          edrpou: legal_entity.edrpou,
          drfo: employee_owner.party.tax_id,
          surname: employee_owner.party.last_name
        },
        %{
          edrpou: nhs_signer.legal_entity.edrpou,
          drfo: nhs_signer.party.tax_id,
          surname: nhs_signer.party.last_name
        },
        %{
          edrpou: nhs_signer.legal_entity.edrpou,
          drfo: nhs_signer.party.tax_id,
          surname: nhs_signer.party.last_name,
          is_stamp: true
        }
      ])

      assert resp =
               conn
               |> patch(contract_request_path(conn, :sign_msp, @capitation, contract_request.id), %{
                 "signed_content" => data |> Poison.encode!() |> Base.encode64(),
                 "signed_content_encoding" => "base64"
               })
               |> json_response(502)
    end

    test "fail with incorrect contractor legal entity status", %{conn: conn} do
      msp()
      template()

      expect(MediaStorageMock, :store_signed_content, fn _, bucket, _, _ ->
        assert :contract_bucket == bucket
        {:ok, "success"}
      end)

      expect(KafkaMock, :publish_to_event_manager, fn _ -> :ok end)

      id = UUID.generate()

      data = %{
        "id" => id,
        "printout_content" => nil,
        "status" => CapitationContractRequest.status(:nhs_signed)
      }

      %{
        "client_id" => client_id,
        "user_id" => user_id,
        "contract_request" => contract_request,
        "legal_entity" => legal_entity,
        "contractor_owner_id" => employee_owner,
        "nhs_signer" => nhs_signer
      } =
        prepare_nhs_sign_params(
          [id: id, data: data, status: CapitationContractRequest.status(:nhs_signed), contract_number: "1345"],
          status: LegalEntity.status(:closed)
        )

      conn =
        conn
        |> put_client_id_header(client_id)
        |> put_consumer_id_header(user_id)
        |> put_req_header("msp_drfo", legal_entity.edrpou)

      expect_signed_content(data, [
        %{
          edrpou: legal_entity.edrpou,
          drfo: employee_owner.party.tax_id,
          surname: employee_owner.party.last_name
        },
        %{
          edrpou: nhs_signer.legal_entity.edrpou,
          drfo: nhs_signer.party.tax_id,
          surname: nhs_signer.party.last_name
        },
        %{
          edrpou: nhs_signer.legal_entity.edrpou,
          drfo: nhs_signer.party.tax_id,
          surname: nhs_signer.party.last_name,
          is_stamp: true
        }
      ])

      resp =
        conn
        |> patch(contract_request_path(conn, :sign_msp, @capitation, contract_request.id), %{
          "signed_content" => data |> Poison.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(422)

      assert %{
               "type" => "validation_failed",
               "invalid" => [
                 %{
                   "entry" => "$.contractor_legal_entity_id",
                   "rules" => [%{"description" => "Legal entity is not active"}]
                 }
               ]
             } = resp["error"]
    end

    test "fail with contractor legal entity not passed NHS verification", %{conn: conn} do
      msp()
      template()

      expect(MediaStorageMock, :store_signed_content, fn _, bucket, _, _ ->
        assert :contract_bucket == bucket
        {:ok, "success"}
      end)

      expect(KafkaMock, :publish_to_event_manager, fn _ -> :ok end)

      id = UUID.generate()

      data = %{
        "id" => id,
        "printout_content" => nil,
        "status" => CapitationContractRequest.status(:nhs_signed)
      }

      %{
        "client_id" => client_id,
        "user_id" => user_id,
        "contract_request" => contract_request,
        "legal_entity" => legal_entity
      } =
        prepare_nhs_sign_params(
          [id: id, data: data, status: CapitationContractRequest.status(:nhs_signed), contract_number: "1345"],
          nhs_verified: false
        )

      resp =
        conn
        |> put_client_id_header(client_id)
        |> put_consumer_id_header(user_id)
        |> put_req_header("msp_drfo", legal_entity.edrpou)
        |> patch(contract_request_path(conn, :sign_msp, @capitation, contract_request.id), %{
          "signed_content" => data |> Poison.encode!() |> Base.encode64(),
          "signed_content_encoding" => "base64"
        })
        |> json_response(409)

      assert %{"message" => "Legal entity is not verified"} = resp["error"]
    end
  end

  describe "get printout_form" do
    test "success get printout_form", %{conn: conn} do
      insert(:il, :dictionary, name: "POSITION", values: %{})
      insert(:il, :dictionary, name: "SETTLEMENT_TYPE", values: %{})
      insert(:il, :dictionary, name: "STREET_TYPE", values: %{})
      insert(:il, :dictionary, name: "SPECIALITY_TYPE", values: %{})
      insert(:il, :dictionary, name: "MEDICAL_SERVICE", values: %{})
      nhs()
      template()

      contract_request =
        insert(:il, :capitation_contract_request, status: CapitationContractRequest.status(:pending_nhs_sign))

      id = contract_request.id

      resp =
        conn
        |> put_client_id_header(UUID.generate())
        |> get(contract_request_path(conn, :printout_content, @capitation, id))
        |> json_response(200)

      assert %{"id" => id, "printout_content" => "<html></html>"} == resp["data"]
    end

    test "invalid status", %{conn: conn} do
      contract_request = insert(:il, :capitation_contract_request)
      nhs()

      conn =
        conn
        |> put_client_id_header(UUID.generate())
        |> get(contract_request_path(conn, :printout_content, @capitation, contract_request.id))

      assert json_response(conn, 409)
    end
  end

  defp prepare_data(role_name \\ "OWNER", legal_entity_type \\ "MSP") do
    expect(MithrilMock, :get_user_roles, fn _, _, _ ->
      {:ok, %{"data" => [%{"role_name" => role_name}]}}
    end)

    user_id = UUID.generate()
    party_user = insert(:prm, :party_user, user_id: user_id)
    legal_entity = insert(:prm, :legal_entity, nhs_verified: true, type: legal_entity_type)

    division =
      insert(
        :prm,
        :division,
        legal_entity: legal_entity,
        phones: [%{"type" => "MOBILE", "number" => "+380631111111"}]
      )

    employee =
      insert(
        :prm,
        :employee,
        division: division,
        legal_entity_id: legal_entity.id
      )

    owner =
      insert(
        :prm,
        :employee,
        employee_type: Employee.type(:owner),
        party: party_user.party,
        legal_entity_id: legal_entity.id
      )

    %{
      legal_entity: legal_entity,
      employee: employee,
      division: division,
      user_id: user_id,
      owner: owner,
      party_user: party_user
    }
  end

  defp prepare_capitation_params(division, employee, expires_at \\ nil) do
    %{id: external_legal_entity_id} = insert(:prm, :legal_entity)

    expires_at = expires_at || Date.utc_today() |> Date.add(10) |> Date.to_iso8601()

    %{
      "contractor_owner_id" => UUID.generate(),
      "contractor_base" => "на підставі закону про Медичне обслуговування населення",
      "contractor_payment_details" => %{
        "bank_name" => "Банк номер 1",
        "MFO" => "351005",
        "payer_account" => "32009102701026"
      },
      "contractor_rmsp_amount" => 10,
      "id_form" => "5",
      "contractor_employee_divisions" => [
        %{
          "employee_id" => employee.id,
          "staff_units" => 0.5,
          "declaration_limit" => 2000,
          "division_id" => division.id
        }
      ],
      "contractor_divisions" => [division.id],
      "external_contractors" => [
        %{
          "legal_entity_id" => external_legal_entity_id,
          "contract" => %{
            "number" => "1234567",
            "issued_at" => expires_at,
            "expires_at" => expires_at
          },
          "divisions" => [
            %{
              "id" => division.id,
              "medical_service" => "Послуга ПМД"
            }
          ]
        }
      ],
      "external_contractor_flag" => true,
      "start_date" => "2018-01-01",
      "end_date" => "2018-01-01",
      "statute_md5" => "media/upload_contract_request_statute.pdf",
      "additional_document_md5" => "media/upload_contract_request_additional_document.pdf",
      "consent_text" =>
        "Цією заявою Заявник висловлює бажання укласти договір про медичне обслуговування населення за програмою державних гарантій медичного обслуговування населення (далі – Договір) на умовах, визначених в оголошенні про укладення договорів про медичне обслуговування населення (далі – Оголошення). Заявник підтверджує, що: 1. на момент подання цієї заяви Заявник має чинну ліцензію на провадження господарської діяльності з медичної практики та відповідає ліцензійним умовам з медичної практики; 2. Заявник надає медичні послуги, пов’язані з первинною медичною допомогою (далі – ПМД); 3. Заявник зареєстрований в електронній системі охорони здоров’я (далі – Система); 4. уповноважені особи та медичні працівники, які будуть залучені до виконання Договору, зареєстровані в Системі та отримали електронний цифровий підпис (далі – ЕЦП); 5. в кожному місці надання медичних послуг Заявника наявне матеріально-технічне оснащення, передбачене розділом І Примірного табелю матеріально-технічного оснащення закладів охорони здоров’я та фізичних осіб – підприємців, які надають ПМД, затвердженого наказом Міністерства охорони здоров’я України від 26 січня 2018 року № 148; 6. установчими або іншими документами не обмежено право керівника Заявника підписувати договори від імені Заявника без попереднього погодження власника. Якщо таке право обмежено, у тому числі щодо укладання договорів, ціна яких перевищує встановлену суму, Заявник повідомить про це Національну службу здоров’я та отримає необхідні погодження від власника до моменту підписання договору зі сторони Заявника; 7. інформація, зазначена Заявником у цій Заяві та доданих до неї документах, а також інформація, внесена Заявником (його уповноваженими особами) до Системи, є повною та достовірною. Заявник усвідомлює, що у разі зміни інформації, зазначеної Заявником у цій заяві та (або) доданих до неї документах Заявник зобов’язаний повідомити про такі зміни НСЗУ протягом трьох робочих днів з дня настання таких змін шляхом надсилання інформації про такі зміни на електронну пошту dohovir@nszu.gov.ua, з одночасним внесенням таких змін в Систему. Заявник усвідомлює, що законодавством України передбачена відповідальність за подання недостовірної інформації органам державної влади."
    }
  end

  defp prepare_nhs_sign_params(contract_request_params, legal_entity_params \\ []) do
    client_id = UUID.generate()
    params = Keyword.merge([id: client_id, nhs_verified: true], legal_entity_params)
    legal_entity = insert(:prm, :legal_entity, params)
    nhs_legal_entity = insert(:prm, :legal_entity)

    user_id = UUID.generate()
    party_user = insert(:prm, :party_user, user_id: user_id)

    nhs_signer =
      insert(
        :prm,
        :employee,
        party: party_user.party,
        legal_entity: nhs_legal_entity
      )

    division =
      insert(
        :prm,
        :division,
        legal_entity: legal_entity,
        phones: [%{"type" => "MOBILE", "number" => "+380631111111"}]
      )

    employee_doctor = insert(:prm, :employee, legal_entity_id: legal_entity.id, division: division)

    employee_owner =
      insert(
        :prm,
        :employee,
        party: party_user.party,
        legal_entity_id: legal_entity.id,
        employee_type: Employee.type(:owner)
      )

    start_date = contract_start_date()

    params =
      Keyword.merge(
        [
          nhs_signed_date: Date.utc_today(),
          nhs_signer_id: nhs_signer.id,
          nhs_legal_entity_id: nhs_legal_entity.id,
          contractor_legal_entity_id: client_id,
          contractor_owner_id: employee_owner.id,
          contractor_divisions: [division.id],
          contractor_employee_divisions: [
            %{
              "employee_id" => employee_doctor.id,
              "staff_units" => 0.5,
              "declaration_limit" => 2000,
              "division_id" => division.id
            }
          ],
          start_date: start_date
        ],
        contract_request_params
      )

    contract_request = insert(:il, :capitation_contract_request, params)

    %{
      "client_id" => client_id,
      "user_id" => user_id,
      "legal_entity" => legal_entity,
      "contract_request" => contract_request,
      "contractor_owner_id" => employee_owner,
      "nhs_signer" => nhs_signer,
      "party_user" => party_user
    }
  end

  defp assert_error(resp, message) do
    assert %{
             "invalid" => [
               %{"entry_type" => "request", "rules" => [%{"rule" => "json"}]}
             ],
             "message" => ^message,
             "type" => "request_malformed"
           } = resp["error"]
  end

  defp assert_error(resp, entry, description, rule \\ "invalid") do
    assert %{
             "type" => "validation_failed",
             "invalid" => [
               %{
                 "rules" => [
                   %{
                     "rule" => ^rule,
                     "description" => ^description
                   }
                 ],
                 "entry_type" => "json_data_property",
                 "entry" => ^entry
               }
             ]
           } = resp["error"]
  end

  defp contract_start_date() do
    Date.add(Date.utc_today(), 1)
  end
end
