defmodule Bonfire.Mailer.PGP.KeyLookupTest do
  use ExUnit.Case, async: true

  alias Bonfire.Mailer.PGP.KeyLookup

  @fake_key """
  -----BEGIN PGP PUBLIC KEY BLOCK-----
  mDMEY2FrZRYJKwYBBAHaRw8BAQdAFakeKeyDataForTesting==
  -----END PGP PUBLIC KEY BLOCK-----
  """

  setup do
    Req.Test.stub(:pgp_key_lookup, fn conn ->
      Req.Test.transport_error(conn, :econnrefused)
    end)

    Process.put([:bonfire_mailer, KeyLookup, :req_options], plug: {Req.Test, :pgp_key_lookup})

    :ok
  end

  describe "wkd_hash (via lookup URL construction)" do
    test "produces correct z-base-32 hash for known input" do
      # bernhard.reiter@intevation.de → it5sewh54rxz33fwmr8u6dy4bbz8itz4
      Req.Test.stub(:pgp_key_lookup, fn conn ->
        if conn.host != "keys.openpgp.org" do
          assert String.contains?(conn.request_path, "it5sewh54rxz33fwmr8u6dy4bbz8itz4")
        end

        Plug.Conn.send_resp(conn, 404, "")
      end)

      KeyLookup.lookup("bernhard.reiter@intevation.de")
    end

    test "lowercases the local part before hashing" do
      urls = :ets.new(:urls, [:bag, :public])

      Req.Test.stub(:pgp_key_lookup, fn conn ->
        :ets.insert(urls, {:url, conn.request_path})
        Plug.Conn.send_resp(conn, 404, "")
      end)

      KeyLookup.lookup("User@Example.com")
      KeyLookup.lookup("user@example.com")

      paths = :ets.lookup(urls, :url) |> Enum.map(fn {:url, p} -> p end)
      # Only WKD paths contain /hu/; skip keyserver paths which have no hash
      hashes =
        paths
        |> Enum.filter(&String.contains?(&1, "/hu/"))
        |> Enum.map(&extract_hash/1)
        |> Enum.uniq()

      assert length(hashes) == 1
    end
  end

  describe "lookup/1" do
    test "queries all three sources in parallel" do
      calls = :ets.new(:calls, [:bag, :public])

      Req.Test.stub(:pgp_key_lookup, fn conn ->
        :ets.insert(calls, {:host, conn.host})
        Plug.Conn.send_resp(conn, 404, "")
      end)

      KeyLookup.lookup("user@example.com")

      hosts = :ets.lookup(calls, :host) |> Enum.map(fn {:host, h} -> h end)
      assert "openpgpkey.example.com" in hosts
      assert "example.com" in hosts
      assert "keys.openpgp.org" in hosts
    end

    test "succeeds via WKD advanced method" do
      Req.Test.stub(:pgp_key_lookup, fn conn ->
        if conn.host == "openpgpkey.example.com" do
          Plug.Conn.send_resp(conn, 200, @fake_key)
        else
          Plug.Conn.send_resp(conn, 404, "")
        end
      end)

      assert {:ok, key} = KeyLookup.lookup("user@example.com")
      assert String.contains?(key, "-----BEGIN PGP PUBLIC KEY BLOCK-----")
    end

    test "succeeds via WKD direct method" do
      Req.Test.stub(:pgp_key_lookup, fn conn ->
        if conn.host == "example.com" do
          Plug.Conn.send_resp(conn, 200, @fake_key)
        else
          Plug.Conn.send_resp(conn, 404, "")
        end
      end)

      assert {:ok, key} = KeyLookup.lookup("user@example.com")
      assert String.contains?(key, "-----BEGIN PGP PUBLIC KEY BLOCK-----")
    end

    test "succeeds via keyserver" do
      Req.Test.stub(:pgp_key_lookup, fn conn ->
        if conn.host == "keys.openpgp.org" do
          Plug.Conn.send_resp(conn, 200, @fake_key)
        else
          Plug.Conn.send_resp(conn, 404, "")
        end
      end)

      assert {:ok, key} = KeyLookup.lookup("user@example.com")
      assert String.contains?(key, "-----BEGIN PGP PUBLIC KEY BLOCK-----")
    end

    test "returns not_found when all sources return 404" do
      Req.Test.stub(:pgp_key_lookup, fn conn ->
        Plug.Conn.send_resp(conn, 404, "")
      end)

      assert {:error, :not_found} = KeyLookup.lookup("nobody@example.com")
    end

    test "returns not_found on network error" do
      Req.Test.stub(:pgp_key_lookup, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, :not_found} = KeyLookup.lookup("nobody@example.com")
    end
  end

  defp extract_hash(path) do
    path |> String.split("/hu/") |> List.last() |> String.split("?") |> List.first()
  end
end
