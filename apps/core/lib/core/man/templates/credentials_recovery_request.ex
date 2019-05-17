defmodule Core.Man.Templates.CredentialsRecoveryRequest do
  @moduledoc false
  use Confex, otp_app: :core

  alias Core.Man.Client, as: ManClient
  alias Core.Users.CredentialsRecoveryRequest

  def render(%CredentialsRecoveryRequest{id: id, user_id: user_id}, client_id, redirect_uri) do
    template_data = %{
      credentials_recovery_request_id: id,
      user_id: user_id,
      client_id: client_id,
      redirect_uri: redirect_uri,
      format: config()[:format],
      locale: config()[:locale]
    }

    template_id = config()[:id]

    ManClient.render_template(template_id, template_data)
  end
end
