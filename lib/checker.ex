# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Mailer.Checker do
  @moduledoc """
  Functions for checking the validity of email addresses and domains
  """
  alias EmailChecker.Check.Format
  alias EmailChecker.Check.MX

  @type error_reason :: :format | :mx

  @spec validate_email(email :: binary) :: :ok | {:error, error_reason}
  @doc """
  Checks whether an email address is valid, returns a reason if not.

  This function can perform two types of checks:
  1. Format check: Ensures the email address has a valid format.
  2. MX record check: Verifies the existence of MX records for the email domain.

  The checks are enabled by default but can be disabled with `check_format: false` and `check_mx: false` on the `:bonfire_mailer` configuration.

  ## Parameters

    - email: The email address to validate as a binary string.

  ## Returns

    - `:ok` if the email is valid.
    - `{:error, :format}` if the email format is invalid.
    - `{:error, :mx}` if the email domain has no valid MX records.

  ## Examples

      iex> Bonfire.Mailer.Checker.validate_email("user@example.com")
      :ok

      iex> Bonfire.Mailer.Checker.validate_email("invalid-email")
      {:error, :format}

      iex> Bonfire.Mailer.Checker.validate_email("user@nonexistent-domain.com")
      {:error, :mx}
  """
  def validate_email(email) do
    config = Bonfire.Common.Config.get_ext(:bonfire_mailer)
    check_format = Keyword.get(config, :check_format, true)
    check_mx = Keyword.get(config, :check_mx, true)

    cond do
      check_format and not Format.valid?(email) -> {:error, :format}
      check_mx and not MX.valid?(email) -> {:error, :mx}
      true -> :ok
    end
  end

  @domain_regex ~r/(?=^.{4,253}$)(^((?!-)[a-zA-Z0-9-]{1,63}(?<!-)\.)+[a-zA-Z]{2,63}$)/

  @spec validate_domain(domain :: binary) :: :ok | {:error, error_reason}
  @doc """
  Checks whether an email domain name is valid, returns a reason if not.

  This function first checks if the domain matches a valid domain format using a regex.
  If the format is valid, it then performs the same checks as `validate_email/1` on a test email address.

  ## Parameters

    - domain: The domain to validate as a binary string.

  ## Returns

    - `:ok` if the domain is valid.
    - `{:error, :format}` if the domain format is invalid.
    - `{:error, :mx}` if the domain has no valid MX records.

  ## Examples

      iex> Bonfire.Mailer.Checker.validate_domain("example.com")
      :ok

      iex> Bonfire.Mailer.Checker.validate_domain("invalid-domain")
      {:error, :format}

      iex> Bonfire.Mailer.Checker.validate_domain("nonexistent-domain.com")
      {:error, :mx}
  """
  def validate_domain(domain) do
    if Regex.match?(@domain_regex, domain) do
      validate_email("test@" <> domain)
    else
      {:error, :format}
    end
  end
end
