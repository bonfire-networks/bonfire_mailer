defmodule Bonfire.Mailer.PGP.KeyLookup do
  @moduledoc """
  Looks up PGP public keys for email addresses via WKD and keys.openpgp.org.

  Runs WKD advanced, WKD direct, and keys.openpgp.org all in parallel,
  returning the first success and cancelling the rest.
  """

  use Untangle
  use Bonfire.Common.Config

  @timeout 5_000

  @doc """
  Looks up a PGP public key for the given email address.

  Returns `{:ok, key_binary}` if found, `{:error, :not_found}` otherwise.
  """
  def lookup(email) do
    [local, domain] = String.split(email, "@", parts: 2)
    hash = wkd_hash(local)
    encoded = URI.encode_www_form(local)

    Bonfire.Common.Utils.apply_async_first_ok(
      [
        fn -> wkd_advanced(domain, hash, encoded) end,
        fn -> wkd_direct(domain, hash, encoded) end,
        fn -> keyserver_lookup(email) end
      ],
      timeout: @timeout
    )
  end

  def wkd_advanced(domain, hash, encoded) do
    fetch("https://openpgpkey.#{domain}/.well-known/openpgpkey/#{domain}/hu/#{hash}?l=#{encoded}")
  end

  def wkd_direct(domain, hash, encoded) do
    fetch("https://#{domain}/.well-known/openpgpkey/hu/#{hash}?l=#{encoded}")
  end

  def keyserver_lookup(email) do
    fetch("https://keys.openpgp.org/vks/v1/by-email/#{URI.encode_www_form(email)}")
  end

  defp fetch(url) do
    extra_opts = Bonfire.Common.Config.get([__MODULE__, :req_options], [])

    case Req.get(url, [decode_body: false, retry: false, redirect: false] ++ extra_opts) do
      {:ok, %{status: 200, body: body}} when body != "" and body != nil ->
        if pgp_key?(body) do
          {:ok, body}
        else
          debug(url, "WKD/keyserver returned non-PGP body (HTML page or other)")
          {:error, :not_found}
        end

      {:ok, %{status: status}} ->
        debug(url, "WKD/keyserver returned #{status}")
        {:error, :not_found}

      {:error, reason} ->
        debug(reason, "WKD/keyserver request failed for #{url}")
        {:error, :not_found}
    end
  end

  # OpenPGP packet tags: old-format (0x80–0xBF) or new-format (0xC0–0xFF)
  defp pgp_key?(<<byte, _::binary>>) when byte >= 0x80, do: true
  defp pgp_key?(<<"-----BEGIN PGP", _::binary>>), do: true
  defp pgp_key?(_), do: false

  # SHA1 of lowercased local part, encoded as z-base-32 (WKD spec)
  def wkd_hash(local) do
    local
    |> String.downcase()
    |> then(&:crypto.hash(:sha, &1))
    |> zbase32_encode()
  end

  defp zbase32_encode(binary) do
    alphabet = "ybndrfg8ejkmcpqxot1uwisza345h769"
    bits = for <<bit::1 <- binary>>, do: bit

    bits
    |> Enum.chunk_every(5, 5, [0, 0, 0, 0])
    |> Enum.map(fn chunk ->
      index = Enum.reduce(chunk, 0, fn b, acc -> acc * 2 + b end)
      String.at(alphabet, index)
    end)
    |> Enum.join()
  end
end
