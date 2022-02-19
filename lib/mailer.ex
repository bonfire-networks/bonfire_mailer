defmodule Bonfire.Mailer do
  use Bamboo.Mailer, otp_app: Bonfire.Common.Config.get!(:otp_app)
  alias Bamboo.Email
  import Where

  def send_now(email, to) do
    from =
      Bonfire.Common.Config.get(__MODULE__, [])
      |> Keyword.get(:reply_to, "noreply@bonfire.local")
    try do
      mail =
        email
        |> Email.from(from)
        |> Email.to(to)

      deliver_now(mail)

      {:ok, mail}
    rescue
      error ->
        handle_error(error)
    end
  end

  def handle_error(error) do
    e = Map.get(error, :raw, error)
    error("Email delivery error: #{inspect(e)}")
    case e do
      {:no_credentials, _} -> {:error, :mailer_config}
      {:retries_exceeded, _} -> {:error, :mailer_retries_exceeded}
      %Bamboo.ApiError{message: msg} -> {:error, :mailer_api_error}
      _ -> {:error, :mailer} # give up
    end
  end

end
