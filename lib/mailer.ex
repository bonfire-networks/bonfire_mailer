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

  def app_name do
    Config.get(
      [:ui, :theme, :instance_name],
      Utils.maybe_apply(Bonfire.Application, :name_and_flavour, [], fallback_return: "Bonfire")
    )
  end

  defp send_impl(email_content, to, mode, opts) when is_binary(email_content) do
    new()
    |> text_body(email_content)
    |> send_impl(to, mode, opts)
  end

  defp send_impl(%{} = email, to, mode, opts) when is_struct(email) do
    from = opts[:from] || Config.get([Bonfire.Mailer, :reply_to]) || @default_email

    already_to = Enum.map(email.to || [], fn {_name, addr} -> addr end)

    email =
      email
      |> then(fn e -> if to in already_to, do: e, else: to(e, to) end)
      |> from(from)
      |> maybe_subject(opts[:subject])

    errors =
      Bonfire.Mailer.PGP.prepare_deliveries(email)
      |> Enum.flat_map(fn prepared ->
        prepared |> info("email to deliver")

        case deliver_prepared(mode, prepared) do
          {:ok, _} -> []
          {:error, e} -> [e]
          other -> [other]
        end
      end)

    case errors do
      [] -> {:ok, email}
      errors -> handle_error(errors)
    end
  rescue
    error ->
      handle_error(error, __STACKTRACE__)
  end

  defp maybe_subject(email, nil), do: email
  defp maybe_subject(email, subject), do: email |> subject(subject)

  defp deliver_prepared(_mode, %{to: [], cc: cc, bcc: bcc}) do
    addrs = Enum.map((cc || []) ++ (bcc || []), fn {_name, addr} -> addr end)

    warn(
      addrs,
      "Cannot deliver email with no `to` recipients — cc/bcc-only emails are not supported"
    )

    {:error, {:no_to_recipients, addrs}}
  end

  defp deliver_prepared(mode, email), do: do_deliver(mode, email)

  defp do_deliver(:async, email), do: deliver_async(email)
  defp do_deliver(_, email), do: deliver_inline(email)

  def handle_error(error, stacktrace \\ nil) do
    e = e(error, :raw, nil) || error
    error(stacktrace, "Email delivery error: #{inspect(e)}")

    case e do
      {:no_credentials, _} -> {:error, :mailer_config}
      {:retries_exceeded, _} -> {:error, :mailer_retries_exceeded}
      %Swoosh.DeliveryError{} -> {:error, :mailer_api_error}
      %{reason: :timeout} -> {:error, :mailer_timeout}
      {:no_to_recipients, addrs} -> {:error, {:no_to_recipients, addrs}}
      errors when is_list(errors) -> {:error, {:partial_failure, errors}}
      _ -> {:error, :mailer}
    end
  end
end
