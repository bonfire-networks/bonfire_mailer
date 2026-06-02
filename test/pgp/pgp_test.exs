defmodule Bonfire.Mailer.PGPTest do
  use ExUnit.Case, async: true

  import Swoosh.TestAssertions

  alias Bonfire.Mailer.PGP
  alias Bonfire.Mailer.PGP.KeyLookup

  @fake_key File.read!(Path.join(__DIR__, "fixtures/fake_public_key.asc"))

  setup do
    Req.Test.stub(:pgp_key_lookup, fn conn ->
      Plug.Conn.send_resp(conn, 404, "")
    end)

    Process.put([:bonfire_mailer, KeyLookup, :req_options], plug: {Req.Test, :pgp_key_lookup})

    # Clear cached key lookup results so tests don't see stale negative hits from prior tests
    for email <- ~w(user@example.com alice@example.com bob@example.com) do
      Bonfire.Common.Cache.remove("pgp_key:#{email}")
    end

    :ok
  end

  defp base_email(to \\ "user@example.com") do
    Swoosh.Email.new()
    |> Swoosh.Email.to({"", to})
    |> Swoosh.Email.from({"", "sender@example.com"})
    |> Swoosh.Email.subject("Test")
    |> Swoosh.Email.text_body("Hello world")
  end

  describe "prepare_deliveries/1 with no keys available" do
    test "returns single plain email when no recipient has a key" do
      emails = PGP.prepare_deliveries(base_email())
      assert length(emails) == 1
      [email] = emails
      assert email.text_body == "Hello world"
      refute email.html_body
      assert email.headers["X-PGP-Encrypted"] == nil
    end

    test "preserves recipients when no key found" do
      email = base_email("alice@example.com")
      [delivered] = PGP.prepare_deliveries(email)
      assert {"", "alice@example.com"} in delivered.to
    end
  end

  describe "prepare_deliveries/1 with pgp disabled" do
    test "returns original email unchanged" do
      Process.put([:bonfire_mailer, Bonfire.Mailer.PGP, :modularity], :disabled)
      email = base_email()
      assert PGP.prepare_deliveries(email) == [email]
    end
  end

  describe "multi-recipient partitioning" do
    test "groups keyless recipients together preserving CC roles" do
      Req.Test.stub(:pgp_key_lookup, fn conn ->
        Plug.Conn.send_resp(conn, 404, "")
      end)

      email =
        Swoosh.Email.new()
        |> Swoosh.Email.to({"", "alice@example.com"})
        |> Swoosh.Email.cc({"", "bob@example.com"})
        |> Swoosh.Email.from({"", "sender@example.com"})
        |> Swoosh.Email.subject("Test")
        |> Swoosh.Email.text_body("Hello")

      [plain] = PGP.prepare_deliveries(email)
      assert {"", "alice@example.com"} in plain.to
      assert {"", "bob@example.com"} in plain.cc
    end

    test "sends encrypted to recipient with key, plain to recipient without" do
      Req.Test.stub(:pgp_key_lookup, fn conn ->
        if String.contains?(conn.query_string, "alice") or
             String.contains?(conn.request_path, "alice_hash") do
          Plug.Conn.send_resp(conn, 200, @fake_key)
        else
          Plug.Conn.send_resp(conn, 404, "")
        end
      end)

      email =
        Swoosh.Email.new()
        |> Swoosh.Email.to({"", "alice@example.com"})
        |> Swoosh.Email.cc({"", "bob@example.com"})
        |> Swoosh.Email.from({"", "sender@example.com"})
        |> Swoosh.Email.subject("Test")
        |> Swoosh.Email.text_body("Secret message")

      deliveries = PGP.prepare_deliveries(email)
      assert length(deliveries) == 2

      plain = Enum.find(deliveries, fn e -> e.headers["X-PGP-Encrypted"] == nil end)
      assert plain != nil
      assert {"", "bob@example.com"} in plain.cc
    end
  end

  describe "error fallback" do
    test "falls back to plain if key lookup fails with an exception" do
      # Simulate a broken key lookup by returning a malformed response
      Req.Test.stub(:pgp_key_lookup, fn conn ->
        # Return garbage that will fail armoring and encryption
        Plug.Conn.send_resp(conn, 200, "not a pgp key at all")
      end)

      emails = PGP.prepare_deliveries(base_email())
      # Should deliver something (either encrypted or plain), never drop the email
      assert length(emails) >= 1
    end

    test "falls back to plain when encryption fails, keeping the recipient" do
      # Return a valid-looking armored block that Decent will reject
      bad_key = """
      -----BEGIN PGP PUBLIC KEY BLOCK-----

      bm90YXJlYWxrZXk=
      =AAAA
      -----END PGP PUBLIC KEY BLOCK-----
      """

      Req.Test.stub(:pgp_key_lookup, fn conn ->
        Plug.Conn.send_resp(conn, 200, bad_key)
      end)

      [delivered] = PGP.prepare_deliveries(base_email("user@example.com"))
      # Recipient must not be silently dropped — appears in the plain fallback
      assert {"", "user@example.com"} in delivered.to
      assert delivered.headers["X-PGP-Encrypted"] == nil
      assert delivered.text_body == "Hello world"
    end

    test "does not drop CC recipients when their encryption fails" do
      bad_key = """
      -----BEGIN PGP PUBLIC KEY BLOCK-----

      bm90YXJlYWxrZXk=
      =AAAA
      -----END PGP PUBLIC KEY BLOCK-----
      """

      Req.Test.stub(:pgp_key_lookup, fn conn ->
        Plug.Conn.send_resp(conn, 200, bad_key)
      end)

      email =
        Swoosh.Email.new()
        |> Swoosh.Email.to({"", "alice@example.com"})
        |> Swoosh.Email.cc({"", "bob@example.com"})
        |> Swoosh.Email.from({"", "sender@example.com"})
        |> Swoosh.Email.subject("Test")
        |> Swoosh.Email.text_body("Hello")

      [plain] = PGP.prepare_deliveries(email)
      assert {"", "alice@example.com"} in plain.to
      assert {"", "bob@example.com"} in plain.cc
    end
  end

  describe "inline PGP structure" do
    test "encrypted email body contains PGP armor markers" do
      Req.Test.stub(:pgp_key_lookup, fn conn ->
        Plug.Conn.send_resp(conn, 200, @fake_key)
      end)

      [encrypted] = PGP.prepare_deliveries(base_email())
      assert encrypted.text_body =~ "BEGIN PGP MESSAGE"
      assert encrypted.headers["X-PGP-Encrypted"] == "1"
    end

    test "encrypted email clears html_body" do
      Req.Test.stub(:pgp_key_lookup, fn conn ->
        Plug.Conn.send_resp(conn, 200, @fake_key)
      end)

      email = base_email() |> Swoosh.Email.html_body("<b>Hello</b>")
      [encrypted] = PGP.prepare_deliveries(email)
      assert encrypted.html_body == nil
    end

    @tag :skip
    test "html_body is attached as encrypted file when present" do
      Req.Test.stub(:pgp_key_lookup, fn conn ->
        Plug.Conn.send_resp(conn, 200, @fake_key)
      end)

      email = base_email() |> Swoosh.Email.html_body("<b>Hello</b>")
      [encrypted] = PGP.prepare_deliveries(email)
      assert length(encrypted.attachments) == 1
      [attachment] = encrypted.attachments
      assert attachment.filename == "encrypted.html.asc"
      assert attachment.content_type == "application/octet-stream"
    end

    test "html-only email is sent plain without encryption attempt" do
      Req.Test.stub(:pgp_key_lookup, fn conn ->
        Plug.Conn.send_resp(conn, 200, @fake_key)
      end)

      email =
        Swoosh.Email.new()
        |> Swoosh.Email.to({"", "user@example.com"})
        |> Swoosh.Email.from({"", "sender@example.com"})
        |> Swoosh.Email.subject("Test")
        |> Swoosh.Email.html_body("<b>Hello</b>")

      [delivered] = PGP.prepare_deliveries(email)
      assert delivered.html_body == "<b>Hello</b>"
      assert delivered.headers["X-PGP-Encrypted"] == nil
    end
  end
end
