defmodule Bonfire.Mailer do
  alias Bonfire.Common.Config
  use Bamboo.Mailer, otp_app: Config.get!(:otp_app)
  alias Bamboo.Email
  import Untangle

  def send_now(email, to, opts \\ []) do
    config = Config.get(__MODULE__, [])

    from = opts[:from] || Keyword.get(config, :reply_to, "noreply@bonfire.local")

    try do
      mail =
        email
        |> Email.from(from)
        |> Email.to(to)

      deliver_now(mail)

      {:ok, mail}
    rescue
      error ->
        handle_error(error, __STACKTRACE__)
    end
  end

  def send_app_feedback(type \\ "feedback", subject, body) do
    config = Config.get(__MODULE__, [])
    # Keyword.get(config, :feedback_from, "team@bonfire.cafe")
    from = Keyword.get(config, :reply_to, "noreply@bonfire.local")
    to = Keyword.get(config, :feedback_to, "bonfire@fire.fundersclub.com")

    app_name = Bonfire.Application.name()

    Email.new_email(
      subject: "#{subject} - #{app_name} #{type}",
      text_body: body
    )
    |> send_now(to, from: from)
  end

  def handle_error(error, stacktrace \\ nil) do
    e = Map.get(error, :raw, error)
    error(stacktrace, "Email delivery error: #{inspect(e)}")

    case e do
      {:no_credentials, _} -> {:error, :mailer_config}
      {:retries_exceeded, _} -> {:error, :mailer_retries_exceeded}
      %Bamboo.ApiError{message: msg} -> {:error, :mailer_api_error}
      # give up
      _ -> {:error, :mailer}
    end
  end
end
