defmodule Bonfire.Mailer.Swoosh do
  @behaviour Bonfire.Mailer.Behaviour

  use Swoosh.Mailer, otp_app: :bonfire_mailer

  defdelegate new(data \\ []), to: Swoosh.Email
  defdelegate to(email, address), to: Swoosh.Email
  defdelegate from(email, address), to: Swoosh.Email
  defdelegate subject(email, subject), to: Swoosh.Email
  defdelegate text_body(email, body), to: Swoosh.Email
  defdelegate html_body(email, body), to: Swoosh.Email

  def deliver_inline(email), do: deliver(email, config())

  def deliver_async(email) do
    Task.Supervisor.start_child(Bonfire.Mailer.AsyncEmailSupervisor, fn ->
      deliver(email, config())
    end)
  end

  # defp config, do: []
  def config, do: Application.get_env(:bonfire_mailer, __MODULE__, [])
end
