defmodule Bonfire.Mailer do
  @moduledoc "./README.md" |> File.stream!() |> Enum.drop(1) |> Enum.join()

  @behaviour Bonfire.Mailer.Behaviour

  use Application
  use Untangle
  use Bonfire.Common.E
  import Bonfire.Mailer.RuntimeConfig, only: [mailer: 0]

  use Bonfire.Common.Config
  alias Bonfire.Common.Utils

  @default_email "noreply@bonfire.local"
  @team_email "team@bonfire.cafe"

  def start(_, _) do
    children = [
      # should come before the endpoint
      {Task.Supervisor, name: Bonfire.Mailer.AsyncEmailSupervisor}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  def new(data \\ []), do: mailer().new(data)
  def to(email, address), do: mailer().to(email, address)
  def from(email, address), do: mailer().from(email, address)
  def subject(email, subject), do: mailer().subject(email, subject)
  def text_body(email, body), do: mailer().text_body(email, body)
  def html_body(email, body), do: mailer().html_body(email, body)
  def deliver_inline(email), do: mailer().deliver_inline(email)
  def deliver_async(email), do: mailer().deliver_async(email)

  def send_now(email, to, opts \\ []),
    do: send_impl(email, to, :now, opts)

  def send_async(email, to, opts \\ []),
    do: send_impl(email, to, :async, opts)

  def send(email, to, mode \\ :async, opts \\ []),
    do: send_impl(email, to, mode, opts)

  def send_app_feedback(subject, body, opts \\ []) do
    to = Config.get([Bonfire.Mailer, :feedback_to]) || @team_email

    send_impl(
      body,
      to,
      opts[:mode] || :async,
      opts ++ [subject: "#{subject} - #{app_name()} #{opts[:type] || "feedback"}"]
    )
  end

  def app_name, do: Utils.maybe_apply(Bonfire.Application, :name, [], fallback_return: "Bonfire")

  defp send_impl(email_content, to, mode, opts) when is_binary(email_content) do
    new()
    |> text_body(email_content)
    |> send_impl(to, mode, opts)
  end

  defp send_impl(%{} = email, to, mode, opts) when is_struct(email) do
    from = opts[:from] || Config.get([Bonfire.Mailer, :reply_to]) || @default_email

    email =
      email
      |> to(to)
      |> from(from)
      |> maybe_subject(opts[:subject])
      |> info()

    case do_deliver(mode, email) do
      {:ok, _result} -> {:ok, email}
      {:error, e} -> handle_error(e)
      other -> handle_error(other)
    end
  rescue
    error ->
      handle_error(error, __STACKTRACE__)
  end

  defp maybe_subject(email, nil), do: email
  defp maybe_subject(email, subject), do: email |> subject(subject)

  defp do_deliver(:async, email), do: deliver_async(email)
  defp do_deliver(_, email), do: deliver_inline(email)

  def handle_error(error, stacktrace \\ nil) do
    e = e(error, :raw, nil) || error
    error(stacktrace, "Email delivery error: #{inspect(e)}")

    case e do
      {:no_credentials, _} -> {:error, :mailer_config}
      {:retries_exceeded, _} -> {:error, :mailer_retries_exceeded}
      %Swoosh.DeliveryError{reason: _reason} -> {:error, :mailer_api_error}
      %Bamboo.ApiError{message: _msg} -> {:error, :mailer_api_error}
      #  we 
      %{reason: :timeout} -> {:error, :mailer_timeout}
      # give up
      _ -> {:error, :mailer}
    end
  end
end
