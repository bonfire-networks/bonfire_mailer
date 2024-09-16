defmodule Bonfire.Mailer.Behaviour do
  @type email :: Swoosh.Email.t() | Bamboo.Email.t()
  @callback new() :: email()
  @callback new(term()) :: email()
  @callback to(email(), String.t() | {String.t(), String.t()}) :: email()
  @callback from(email(), String.t() | {String.t(), String.t()}) :: email()
  @callback subject(email(), String.t()) :: email()
  @callback text_body(email(), String.t()) :: email()
  @callback html_body(email(), String.t()) :: email()
  @callback deliver_inline(email :: email()) :: {:ok, term()} | {:error, term()}
  @callback deliver_async(email :: email()) :: {:ok, term()} | {:error, term()}
end
