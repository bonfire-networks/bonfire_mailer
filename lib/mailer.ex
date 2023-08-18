defmodule Bonfire.Mailer do
  alias Bonfire.Common.Utils
  alias Bonfire.Common.Config
  use Bamboo.Mailer, otp_app: :bonfire_mailer
  alias Bamboo.Email
  import Untangle

  @default_email "noreply@bonfire.local"
  @team_email "team@bonfire.cafe"

  def config, do: Config.get(__MODULE__) || []

  def send_now(email, to, opts \\ []) do
    send(email, to, :now, opts)
  end
  def send_async(email, to, opts \\ []) do
    send(email, to, :async, opts)
  end

  def send(email, to, mode, opts \\ []) do
    from = opts[:from] || Bonfire.Common.Config.get([Bonfire.Mailer, :reply_to]) || @default_email

    try do
      mail =
        email
        |> Email.from(from)
        |> Email.to(to)

      with {:ok, _done} <- do_send(mode, mail) do
        {:ok, mail}
      else
        {:error, e} -> handle_error(e)
        other -> handle_error(other)
      end
    rescue
      error ->
        handle_error(error, __STACKTRACE__)
    end
  end

  def do_send(:async, mail) do
    deliver_later(mail) 
  end
  def do_send(_, mail) do
    deliver_now(mail) 
  end

  def send_app_feedback(type \\ "feedback", subject, body) do
    from = Bonfire.Common.Config.get([Bonfire.Mailer, :reply_to]) || @default_email
    to = Bonfire.Common.Config.get([Bonfire.Mailer, :feedback_to]) || @team_email

    app_name = Bonfire.Application.name()

    Email.new_email(
      subject: "#{subject} - #{app_name} #{type}",
      text_body: body
    )
    |> send_now(to, from: from)
  end

  def handle_error(error, stacktrace \\ nil) do
    e = Utils.e(error, :raw, nil) || error
    error(stacktrace, "Email delivery error: #{inspect(e)}")

    case e do
      {:no_credentials, _} -> {:error, :mailer_config}
      {:retries_exceeded, _} -> {:error, :mailer_retries_exceeded}
      %Bamboo.ApiError{message: _msg} -> {:error, :mailer_api_error}
      # give up
      _ -> {:error, :mailer}
    end
  end
end
