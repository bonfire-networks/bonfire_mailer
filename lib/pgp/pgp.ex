defmodule Bonfire.Mailer.PGP do
  @moduledoc """
  Opportunistic PGP/MIME encryption for outgoing emails.

  When enabled, looks up PGP public keys for each recipient via WKD and
  keyservers. Recipients with keys get individually-encrypted emails.
  Recipients without keys are grouped into one plain email preserving
  their To/CC/BCC roles.
  """

  use Untangle
  use Bonfire.Common.Config
  alias Bonfire.Common.Cache
  alias Bonfire.Mailer.PGP.KeyLookup

  # 60 minutes for successful key lookups
  @ttl_hit :timer.minutes(60)
  # 10 minutes for negative results (avoid hammering for non-PGP users)
  @ttl_miss :timer.minutes(10)

  @doc """
  Partitions and prepares email deliveries, encrypting where possible.

  Returns a list of `%Swoosh.Email{}` structs ready to deliver:
  - One per recipient who has a PGP key (individually encrypted)
  - One for all recipients without keys (plain, preserving To/CC/BCC roles)
  """
  def prepare_deliveries(%Swoosh.Email{} = email) do
    if Config.get([__MODULE__, :modularity]) == :disabled do
      info("PGP disabled via modularity config — sending plain")
      [email]
    else
      do_prepare_deliveries(email)
    end
  end

  defp do_prepare_deliveries(%{text_body: nil} = email), do: [email]
  defp do_prepare_deliveries(%{text_body: ""} = email), do: [email]

  defp do_prepare_deliveries(email) do
    # Only encrypt when email has a plain text body — inline PGP is text-only.
    # Recipients with a PGP key get an individually encrypted copy.
    # Recipients without a key (or when encryption fails) fall back to the
    # original full email (text + HTML preserved).
    {encrypted, fallback_recipients} =
      email
      |> collect_recipients()
      |> Enum.reduce({[], []}, fn {addr, role} = recipient, {enc_acc, plain_acc} ->
        case fetch_key(addr) do
          {:ok, key} ->
            single = email |> clear_recipients() |> Swoosh.Email.to({"", addr})

            case encrypt_email(single, key) do
              nil ->
                # Encryption failed — cached key may be stale/invalid; evict it
                Cache.remove("pgp_key:#{addr}")
                {enc_acc, [recipient | plain_acc]}

              encrypted_email ->
                {[encrypted_email | enc_acc], plain_acc}
            end

          {:error, _} ->
            {enc_acc, [recipient | plain_acc]}
        end
      end)

    plain =
      case Enum.reverse(fallback_recipients) do
        [] -> []
        recipients -> [rebuild_with_recipients(email, recipients)]
      end

    Enum.reverse(encrypted) ++ plain
  end

  defp fetch_key(email) do
    cache_key = "pgp_key:#{email}"

    case Cache.get(cache_key) do
      {:ok, {:ok, key}} ->
        info(email, "PGP key cache hit")
        {:ok, key}

      {:ok, :not_found} ->
        info(email, "PGP key cache hit: not_found")
        {:error, :not_found}

      other ->
        info({email, other}, "PGP key cache miss — looking up")

        case KeyLookup.lookup(email) do
          {:ok, raw_key} ->
            case Decent.extract_key(raw_key) do
              {:ok, key} ->
                info(email, "PGP key found, normalized and caching")
                Cache.put(cache_key, {:ok, key}, expire: @ttl_hit)
                {:ok, key}

              e ->
                warn(e, "PGP key found but could not be normalized, treating as not found")
                Cache.put(cache_key, :not_found, expire: @ttl_miss)
                {:error, :not_found}
            end

          e ->
            info(e, "PGP key not found, caching miss")
            Cache.put(cache_key, :not_found, expire: @ttl_miss)
            {:error, :not_found}
        end
    end
  end

  defp collect_recipients(%Swoosh.Email{to: to, cc: cc, bcc: bcc}) do
    (Enum.map(to || [], fn {_name, addr} -> {addr, :to} end) ++
       Enum.map(cc || [], fn {_name, addr} -> {addr, :cc} end) ++
       Enum.map(bcc || [], fn {_name, addr} -> {addr, :bcc} end))
    |> Enum.uniq_by(fn {addr, _role} -> addr end)
  end

  defp clear_recipients(email), do: %{email | to: [], cc: [], bcc: []}

  defp rebuild_with_recipients(email, recipients) do
    Enum.reduce(recipients, clear_recipients(email), fn {addr, role}, acc ->
      case role do
        :to -> Swoosh.Email.to(acc, {"", addr})
        :cc -> Swoosh.Email.cc(acc, {"", addr})
        :bcc -> Swoosh.Email.bcc(acc, {"", addr})
      end
    end)
  end

  defp encrypt_email(email, key) do
    case Decent.encrypt(email.text_body, key) do
      {:ok, encrypted} when encrypted != email.text_body ->
        build_encrypted_email(email, encrypted, key)
        |> info("Email encrypted successfully")

      {:error, reason} ->
        warn(reason, "PGP encryption failed, sending plain")
        nil

      e ->
        warn(e, "PGP encryption returned something unexpected, sending plain")
        nil
    end
  end

  # TODO: use PGP/MIME (RFC 3156) instead of inline PGP — build a multipart/encrypted MIME tree
  # via :mimemail (gen_smtp) and send via mua using SMTP credentials, which all providers support
  # alongside their API. Need to check how SMTP credentials are exposed when MAIL_BACKEND is
  # an API-based adapter (e.g. mailgun) rather than smtp.
  defp build_encrypted_email(email, encrypted_text, key) do
    email
    |> Map.put(:text_body, encrypted_text)
    |> Map.put(:html_body, nil)
    # |> maybe_attach_encrypted_html(email.html_body, key)
    |> Swoosh.Email.header("X-PGP-Encrypted", "1")
  end

  defp maybe_attach_encrypted_html(email, html, key) when html not in [nil, ""] do
    case Decent.encrypt(html, key) do
      result when is_binary(result) ->
        attach_encrypted(email, result, "encrypted.html.asc")

      {:ok, result} ->
        attach_encrypted(email, result, "encrypted.html.asc")

      _ ->
        email
    end
  end

  defp maybe_attach_encrypted_html(email, _html, _key), do: email

  defp attach_encrypted(email, data, filename) do
    Swoosh.Email.attachment(
      email,
      Swoosh.Attachment.new({:data, data},
        filename: filename,
        content_type: "application/octet-stream",
        type: :attachment
      )
    )
  rescue
    e ->
      warn(e, "Failed to attach encrypted HTML, skipping attachment")
      email
  end
end
