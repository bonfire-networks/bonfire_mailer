defmodule Bonfire.Mailer.PGP.LiveTest do
  @moduledoc """
  Live tests that send real emails - both encrypted and plain.

  Run with:
    LIVE_TEST_SEND_EMAILS=true LIVE_TEST_EMAIL_ENCRYPTED=you@pm.me LIVE_TEST_EMAIL_PLAIN=you@gmail.com just test-live-DRAGONS extensions/bonfire_mailer/test/pgp/pgp_live_test.exs

  LIVE_TEST_EMAIL_ENCRYPTED must have a discoverable PGP key (e.g. a Proton address).
  LIVE_TEST_EMAIL_PLAIN must not have one (e.g. a Gmail address).
  Check both inboxes to verify the correct format was delivered.
  """

  use ExUnit.Case, async: false

  @moduletag :live_federation

  @subject "[Bonfire PGP live test] #{DateTime.utc_now() |> DateTime.to_string()}"
  @text_body "This is a live PGP encryption test from Bonfire.\n\nIf you can read this in plain text, decryption worked (or no key was found and it was sent unencrypted)."
  @html_body "<p>This is a <strong>live PGP encryption test</strong> from Bonfire.</p>"

  setup_all do
    encrypted_addr = System.get_env("LIVE_TEST_EMAIL_ENCRYPTED")
    plain_addr = System.get_env("LIVE_TEST_EMAIL_PLAIN")
    all_emails = Enum.reject([encrypted_addr, plain_addr], &is_nil/1)

    # Evict any stale cached keys so tests always fetch fresh ones
    for email <- all_emails do
      Bonfire.Common.Cache.remove("pgp_key:#{email}")
    end

    {:ok, all_emails: all_emails, explicit_encrypted: encrypted_addr, explicit_plain: plain_addr}
  end

  describe "key lookup" do
    test "resolves PGP key presence for all provided addresses", %{all_emails: emails} do
      for email <- emails do
        case Bonfire.Mailer.PGP.KeyLookup.lookup(email) do
          {:ok, key} ->
            assert is_binary(key) and byte_size(key) > 0
            IO.puts("  ✓ Key found for #{email} (#{byte_size(key)} bytes) — will encrypt")

          {:error, :not_found} ->
            IO.puts("  · No key for #{email} — will send plain")
        end
      end
    end

    test "WKD advanced lookup", %{explicit_encrypted: email} do
      if is_nil(email) do
        IO.puts("  · Skipping — set LIVE_TEST_EMAIL_ENCRYPTED")
      else
        [local, domain] = String.split(email, "@", parts: 2)
        hash = Bonfire.Mailer.PGP.KeyLookup.wkd_hash(local)
        encoded = URI.encode_www_form(local)
        result = Bonfire.Mailer.PGP.KeyLookup.wkd_advanced(domain, hash, encoded)

        IO.puts(
          "  WKD advanced for #{email}: #{inspect(case result do
            {:ok, k} -> {:ok, byte_size(k)}
            other -> other
          end)}"
        )

        case result do
          {:ok, key} -> assert is_binary(key)
          {:error, :not_found} -> IO.puts("  · No WKD advanced key")
        end
      end
    end

    test "WKD direct lookup", %{explicit_encrypted: email} do
      if is_nil(email) do
        IO.puts("  · Skipping — set LIVE_TEST_EMAIL_ENCRYPTED")
      else
        [local, domain] = String.split(email, "@", parts: 2)
        hash = Bonfire.Mailer.PGP.KeyLookup.wkd_hash(local)
        encoded = URI.encode_www_form(local)
        result = Bonfire.Mailer.PGP.KeyLookup.wkd_direct(domain, hash, encoded)

        IO.puts(
          "  WKD direct for #{email}: #{inspect(case result do
            {:ok, k} -> {:ok, byte_size(k)}
            other -> other
          end)}"
        )

        case result do
          {:ok, key} -> assert is_binary(key)
          {:error, :not_found} -> IO.puts("  · No WKD direct key (expected for some domains)")
        end
      end
    end

    test "keyserver lookup", %{explicit_encrypted: email} do
      if is_nil(email) do
        IO.puts("  · Skipping — set LIVE_TEST_EMAIL_ENCRYPTED")
      else
        result = Bonfire.Mailer.PGP.KeyLookup.keyserver_lookup(email)

        IO.puts(
          "  Keyserver for #{email}: #{inspect(case result do
            {:ok, k} -> {:ok, byte_size(k)}
            other -> other
          end)}"
        )

        case result do
          {:ok, key} ->
            assert is_binary(key)

          {:error, :not_found} ->
            IO.puts("  · No keyserver key (common for privacy-first providers)")
        end
      end
    end
  end

  describe "encrypted delivery" do
    test "sends encrypted email to address known to have a PGP key", %{
      explicit_encrypted: encrypted_addr,
      all_emails: all
    } do
      addr = encrypted_addr || Enum.find(all, &has_key?/1)

      if is_nil(addr) do
        IO.puts("  · Skipping — no address with a PGP key found. Set LIVE_TEST_EMAIL_ENCRYPTED.")
      else
        assert {:ok, key} = Bonfire.Mailer.PGP.KeyLookup.lookup(addr),
               "Expected #{addr} to have a PGP key"

        IO.puts(
          "  ✓ Key found for #{addr} (#{byte_size(key)} bytes, armored=#{String.starts_with?(key, "-----BEGIN PGP")})"
        )

        case Decent.encrypt(@text_body, key) do
          {:ok, _} -> IO.puts("  ✓ Encryption succeeded — sending encrypted email")
          {:error, reason} -> IO.puts("  ✗ Encryption FAILED: #{reason}")
        end

        assert {:ok, _} = send_test_email(addr)
        IO.puts("  ✓ Email delivered to #{addr} — check inbox")
      end
    end

    test "sends plain email to address known to have no PGP key", %{
      explicit_plain: plain_addr,
      all_emails: all
    } do
      addr = plain_addr || Enum.find(all, &(!has_key?(&1)))

      if is_nil(addr) do
        IO.puts("  · Skipping — no address without a PGP key found. Set LIVE_TEST_EMAIL_PLAIN.")
      else
        assert {:error, :not_found} = Bonfire.Mailer.PGP.KeyLookup.lookup(addr),
               "Expected #{addr} to have NO PGP key for this test to be meaningful"

        IO.puts("  ✓ No key for #{addr} — sending plain email")
        assert {:ok, _} = send_test_email(addr)
        IO.puts("  ✓ Plain email delivered to #{addr} — check inbox")
      end
    end
  end

  describe "mixed delivery" do
    test "correctly splits encrypted/plain when sending to multiple recipients", %{
      explicit_encrypted: encrypted_addr,
      explicit_plain: plain_addr,
      all_emails: all
    } do
      enc = encrypted_addr || Enum.find(all, &has_key?/1)
      plain = plain_addr || Enum.find(all, &(!has_key?(&1)))

      cond do
        is_nil(enc) ->
          IO.puts("  · Skipping mixed test — no PGP-capable address available")

        is_nil(plain) ->
          IO.puts("  · Skipping mixed test — no plain address available")

        true ->
          IO.puts("  Sending mixed email: encrypted to #{enc}, plain to #{plain}")

          email =
            Swoosh.Email.new()
            |> Swoosh.Email.to([{"", enc}, {"", plain}])
            |> Swoosh.Email.subject(@subject <> " [mixed]")
            |> Swoosh.Email.text_body(@text_body)
            |> Swoosh.Email.html_body(@html_body)

          # Verify partitioning before sending — must produce 2 separate deliveries
          deliveries = Bonfire.Mailer.PGP.prepare_deliveries(email)

          assert length(deliveries) == 2,
                 "Expected 2 separate deliveries (1 encrypted + 1 plain), got #{length(deliveries)} — emails are being sent together!"

          enc_delivery = Enum.find(deliveries, &(&1.headers["X-PGP-Encrypted"] == "1"))
          plain_delivery = Enum.find(deliveries, &(&1.headers["X-PGP-Encrypted"] != "1"))

          assert enc_delivery != nil, "Expected an encrypted delivery for #{enc}"
          assert plain_delivery != nil, "Expected a plain delivery for #{plain}"
          IO.puts("  ✓ Partitioning correct: 1 encrypted + 1 plain")

          assert {:ok, _} = Bonfire.Mailer.send_now(email, enc, [])
          IO.puts("  ✓ Mixed delivery done — check both inboxes")
      end
    end
  end

  defp send_test_email(to) do
    Bonfire.Mailer.send_now(
      Swoosh.Email.new()
      |> Swoosh.Email.subject(@subject)
      |> Swoosh.Email.text_body(@text_body)
      |> Swoosh.Email.html_body(@html_body),
      to,
      []
    )
  end

  defp has_key?(email) do
    match?({:ok, _}, Bonfire.Mailer.PGP.KeyLookup.lookup(email))
  end
end
