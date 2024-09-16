defmodule Bonfire.Mailer.Bamboo do
  @behaviour Bonfire.Mailer.Behaviour

  use Bamboo.Mailer, otp_app: :bonfire_mailer
  import Untangle

  defdelegate new(data \\ []), to: Bamboo.Email, as: :new_email
  defdelegate to(email, address), to: Bamboo.Email
  defdelegate from(email, address), to: Bamboo.Email
  defdelegate subject(email, subject), to: Bamboo.Email
  defdelegate text_body(email, body), to: Bamboo.Email
  defdelegate html_body(email, body), to: Bamboo.Email

  def deliver_inline(email), do: deliver_now(email, config())

  def deliver_async(email), do: deliver_later(email, config())

  defp config, do: Application.get_env(:bonfire_mailer, __MODULE__)
end
