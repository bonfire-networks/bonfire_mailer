defmodule Bonfire.Mailer do
  @moduledoc "./README.md" |> File.stream!() |> Enum.drop(1) |> Enum.join()

  alias Bonfire.Common.Utils
  alias Bonfire.Common.Config
  use Bamboo.Mailer, otp_app: :bonfire_mailer
  alias Bamboo.Email
  import Untangle

  @default_email "noreply@bonfire.local"
  @team_email "team@bonfire.cafe"

  @doc """
  Retrieves the configuration for the Bonfire.Mailer module.

  ## Examples

      iex> Bonfire.Mailer.config()
      [key: "value"]
  """
  def config, do: Config.get(__MODULE__) || []

  @doc """
  Sends an email immediately.

  ## Parameters

    - email: The email content to be sent.
    - to: The recipient's email address.
    - opts: Optional parameters for sending the email.

  ## Examples

      iex> Bonfire.Mailer.send_now("Hello", "recipient@example.com")
      {:ok, %Bamboo.Email{}}
  """
  def send_now(email, to, opts \\ []) do
    send(email, to, :now, opts)
  end

  @doc """
  Sends an email asynchronously.

  ## Parameters

    - email: The email content to be sent.
    - to: The recipient's email address.
    - opts: Optional parameters for sending the email.

  ## Examples

      iex> Bonfire.Mailer.send_async("Hello", "recipient@example.com")
      {:ok, %Bamboo.Email{}}
  """
  def send_async(email, to, opts \\ []) do
    send(email, to, :async, opts)
  end

  @doc """
  Sends an email with specified mode (immediate or async).

  ## Parameters

    - email: The email content to be sent.
    - to: The recipient's email address.
    - mode: The sending mode (:now or :async).
    - opts: Optional parameters for sending the email.

  ## Examples

      iex> Bonfire.Mailer.send("Hello", "recipient@example.com", :now)
      {:ok, %Bamboo.Email{}}
  """
  def send(email, to, mode \\ :async, opts \\ []) do
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

  @doc """
  Sends a feedback email to the application maintainers (to the email address configured at `:bonfire_mailer, Bonfire.Mailer, :feedback_to`)

  ## Parameters

    - type: The type of feedback (default: "feedback").
    - subject: The subject of the feedback email.
    - body: The body content of the feedback email.

  ## Examples

      iex> Bonfire.Mailer.send_app_feedback("bug", "Error report", "Found a bug in the system")
      {:ok, %Bamboo.Email{}}
  """
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

  @doc """
  Return a standard error tuple for errors that occur during email sending.

  ## Parameters

    - error: The error that occurred.
    - stacktrace: The stacktrace of the error (optional).

  ## Examples

      iex> Bonfire.Mailer.handle_error(%Bamboo.ApiError{message: "Some API Error"})
      {:error, :mailer_api_error}
  """
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
