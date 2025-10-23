defmodule Bonfire.Mailer.ConnDebug do
  @moduledoc """
  Connectivity and handshake debugging for simple TCP, TLS/SMTPS (implicit TLS like port 465), or SMTP with STARTTLS (like port 587).

  Return values:
  - {:open, :tcp} | {:open, :tls} | {:open, :tls_verified}
  - {:closed, reason} where reason is an atom (e.g., :refused, :timeout, :starttls_not_advertised, etc.)

  Notes:
  - Host can be a binary domain (e.g., "smtp.gmail.com"), a charlist ('smtp.gmail.com'), or an IP tuple.
  - For TLS verification, system CAs are used if available (OTP 26+: :public_key.cacerts_get/0). You can override with :cacerts or :cacertfile in ssl_opts.
  - To force IPv6, include :inet6 in tcp_opts or ssl_opts.
  """

  # =========================
  # Public API
  # =========================

  @doc """
  Checks plain TCP reachability.

  Options:
  - tcp_opts: extra gen_tcp options (default [:binary, packet: :raw, active: false, nodelay: true])

  Examples:
    tcp_port_status("example.com", 443)
  """
  @spec tcp_port_status(
          charlist() | binary() | :inet.ip_address(),
          :inet.port_number(),
          non_neg_integer(),
          keyword()
        ) ::
          {:open, :tcp} | {:closed, term()}
  def tcp_port_status(host, port, timeout \\ 3000, tcp_opts \\ []) do
    host = normalize_host(host)

    opts =
      Keyword.merge(
        [:binary, {:packet, :raw}, {:active, false}, {:nodelay, true}],
        List.wrap(tcp_opts)
      )

    case :gen_tcp.connect(host, port, opts, timeout) do
      {:ok, sock} ->
        :gen_tcp.close(sock)
        {:open, :tcp}

      {:error, :econnrefused} ->
        {:closed, :refused}

      {:error, :timeout} ->
        {:closed, :timeout}

      {:error, reason} ->
        {:closed, reason}
    end
  end

  @doc """
  Attempts a TLS handshake to the host:port (implicit TLS), e.g., HTTPS 443 or SMTPS 465.

  Parameters:
  - host, port, timeout (ms)
  - ssl_opts: options passed to :ssl.connect/4
  - verify: when true, enables certificate verification using system CAs (unless overridden in ssl_opts)

  Examples:
    tls_port_status("smtp.gmail.com", 465)
    tls_port_status("smtp.gmail.com", 465, 5000, [], true)
  """
  @spec tls_port_status(
          charlist() | binary() | :inet.ip_address(),
          :inet.port_number(),
          non_neg_integer(),
          keyword(),
          boolean()
        ) ::
          {:open, :tls} | {:open, :tls_verified} | {:closed, term()}
  def tls_port_status(host, port, timeout \\ 5000, ssl_opts \\ [], verify \\ false) do
    {host, sni_host} = normalize_host_and_sni(host)
    # Use Bonfire.Common.HTTP.Connection.default_ssl_options/1 for SSL defaults
    base_ssl_opts =
      Bonfire.Common.HTTP.Connection.default_ssl_options(ssl_opts)
      |> Keyword.put_new(:server_name_indication, sni_host)

    opts = base_ssl_opts(sni_host, base_ssl_opts, verify)
    IO.inspect(opts, label: "SSL options for tls_port_status")

    case :ssl.connect(host, port, opts, timeout) do
      {:ok, sock} ->
        :ssl.close(sock)
        if verify, do: {:open, :tls_verified}, else: {:open, :tls}

      {:error, :timeout} ->
        {:closed, :timeout}

      {:error, reason} ->
        {:closed, reason}
    end
  end

  @doc """
  SMTPS (implicit TLS) check, defaults to port 465.
  Thin wrapper over tls_port_status/5.
  """
  @spec smtps_port_status(
          charlist() | binary() | :inet.ip_address(),
          :inet.port_number(),
          non_neg_integer(),
          keyword(),
          boolean()
        ) ::
          {:open, :tls} | {:open, :tls_verified} | {:closed, term()}
  def smtps_port_status(host, port \\ 465, timeout \\ 5000, ssl_opts \\ [], verify \\ false) do
    tls_port_status(host, port, timeout, ssl_opts, verify)
  end

  @doc """
  SMTP with STARTTLS check (e.g., port 587). Performs:
  - TCP connect
  - Read 220 greeting
  - EHLO
  - Detect STARTTLS capability
  - Issue STARTTLS
  - Upgrade the socket to TLS

  Options (keyword list):
  - :timeout    -> overall per-step timeout in ms (default 7000)
  - :ehlo_host  -> EHLO client name (charlist or binary), default 'localhost'
  - :ssl_opts   -> options appended to TLS handshake
  - :verify     -> when true, enables certificate verification (default false)
  - :tcp_opts   -> extra gen_tcp options (merged with defaults [:binary, packet: :line, active: false])

  Returns:
  - {:open, :tls} | {:open, :tls_verified}
  - {:closed, reason}
      reasons include: :timeout, :refused, :unexpected_banner, :starttls_not_advertised,
      :starttls_rejected, :handshake_failure, other low-level errors.

  Example:
    smtp_starttls_status("smtp.gmail.com", 587, verify: true)
  """
  @spec smtp_starttls_status(
          charlist() | binary() | :inet.ip_address(),
          :inet.port_number(),
          keyword()
        ) ::
          {:open, :tls} | {:open, :tls_verified} | {:closed, term()}
  def smtp_starttls_status(host, port \\ 587, opts \\ []) do
    {host, sni_host} = normalize_host_and_sni(host)

    timeout = Keyword.get(opts, :timeout, 7000)
    ehlo = normalize_host(Keyword.get(opts, :ehlo_host, 'localhost'))
    ssl_opts = Keyword.get(opts, :ssl_opts, [])
    verify = Keyword.get(opts, :verify, false)

    tcp_opts =
      opts
      |> Keyword.get(:tcp_opts, [])
      |> then(&Keyword.merge([:binary, {:packet, :line}, {:active, false}], &1))

    with {:ok, sock} <- :gen_tcp.connect(host, port, tcp_opts, timeout),
         :ok <- smtp_expect_greeting(sock, timeout),
         :ok <- smtp_send_ehlo(sock, ehlo, timeout),
         :ok <- smtp_expect_starttls_advertised(sock, timeout),
         :ok <- smtp_send_starttls(sock, timeout),
         result <- smtp_upgrade_to_tls(sock, sni_host, timeout, ssl_opts, verify) do
      result
    else
      {:error, :econnrefused} ->
        {:closed, :refused}

      {:error, :timeout} ->
        {:closed, :timeout}

      {:error, reason} ->
        {:closed, reason}
    end
  end

  @doc """
  Sends an SMTP message directly using Mua.easy_send/1, loading host, sender, port, auth, and ssl from mailer config.

  ## Example

      send_smtp_message(["recipient@example.com"], "Subject: ...\\r\\n...")

  Returns {:ok, receipt} or {:error, reason}
  """
  def send_smtp_message(recipients, message, opts \\ []) do
    config = Bonfire.Mailer.Swoosh.config()

    host = opts[:host] || config[:relay]
    sender = opts[:from] || config[:from] || config[:auth][:username]
    port = opts[:port] || config[:port] || 587
    auth = opts[:auth] || config[:auth]
    ssl = opts[:ssl] || config[:ssl] || []
    timeout = opts[:timeout] || config[:timeout] || 5000

    mua_opts =
      [
        auth: auth,
        port: port,
        ssl: ssl,
        protocol: :ssl,
        timeout: timeout
      ]
      |> Keyword.merge(Keyword.drop(opts, [:host, :sender, :port, :auth, :ssl]))
      |> IO.inspect(label: "MUA options for send_smtp_message")

    Mua.easy_send(host, sender, List.wrap(recipients), message, mua_opts)
  end

  # =========================
  # SMTP helpers
  # =========================

  defp smtp_expect_greeting(sock, timeout) do
    # Expect 220 greeting (handle multiline 220- ... 220 <space> ...)
    recv_multiline_code(sock, 220, timeout)
  end

  defp smtp_send_ehlo(sock, ehlo_host, timeout) do
    :ok = :gen_tcp.send(sock, ["EHLO ", ehlo_host, "\r\n"])
    :ok
  end

  defp smtp_expect_starttls_advertised(sock, timeout) do
    # Read EHLO response (one or multiple lines, starting with 250- and ending with 250<space>)
    case recv_collect_until_final(sock, 250, timeout) do
      {:ok, lines} ->
        if Enum.any?(lines, &smtp_line_has_starttls?/1) do
          :ok
        else
          {:error, :starttls_not_advertised}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp smtp_send_starttls(sock, timeout) do
    :ok = :gen_tcp.send(sock, "STARTTLS\r\n")

    case :gen_tcp.recv(sock, 0, timeout) do
      {:ok, line} ->
        case smtp_code_and_sep(line) do
          {220, _sep} -> :ok
          # TLS not available due to temporary reason
          {454, _} -> {:error, :starttls_rejected}
          # Enforce TLS policy
          {534, _} -> {:error, :starttls_rejected}
          # Command not implemented
          {502, _} -> {:error, :starttls_rejected}
          {code, _} when is_integer(code) -> {:error, {:unexpected_code, code}}
          _ -> {:error, :unexpected_response}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp smtp_upgrade_to_tls(tcp_sock, sni_host, timeout, user_ssl_opts, verify) do
    # Use Bonfire.Common.HTTP.Connection.default_ssl_options/1 for SSL defaults
    base_ssl_opts =
      Bonfire.Common.HTTP.Connection.default_ssl_options(user_ssl_opts)
      |> Keyword.put_new(:server_name_indication, sni_host)

    opts = base_ssl_opts(sni_host, base_ssl_opts, verify)
    IO.inspect(opts, label: "SSL options for smtp_upgrade_to_tls")

    case :ssl.connect(tcp_sock, opts, timeout) do
      {:ok, ssl_sock} ->
        :ssl.close(ssl_sock)
        if verify, do: {:open, :tls_verified}, else: {:open, :tls}

      {:error, :timeout} ->
        # TCP socket is still open on failure; close to avoid leak
        safe_close_tcp(tcp_sock)
        {:closed, :timeout}

      {:error, reason} ->
        safe_close_tcp(tcp_sock)
        {:closed, reason}
    end
  end

  defp smtp_line_has_starttls?(line) when is_binary(line) do
    # Case-insensitive search for "STARTTLS" in the line
    String.contains?(String.upcase(line), "STARTTLS")
  end

  defp recv_collect_until_final(sock, expected_code, timeout, acc \\ []) do
    case :gen_tcp.recv(sock, 0, timeout) do
      {:ok, line} ->
        {code, sep} = smtp_code_and_sep(line)

        cond do
          code == expected_code and sep == ?- ->
            recv_collect_until_final(sock, expected_code, timeout, [line | acc])

          code == expected_code and sep == ?\s ->
            {:ok, Enum.reverse([line | acc])}

          true ->
            {:error, :unexpected_response}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp recv_multiline_code(sock, expected_code, timeout) do
    # Reads lines until we see "<code><space>" as the final line.
    case :gen_tcp.recv(sock, 0, timeout) do
      {:ok, line} ->
        {code, sep} = smtp_code_and_sep(line)

        cond do
          code == expected_code and sep == ?- ->
            recv_multiline_code(sock, expected_code, timeout)

          code == expected_code and sep == ?\s ->
            :ok

          is_integer(code) ->
            {:error, :unexpected_banner}

          true ->
            {:error, :unexpected_response}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp smtp_code_and_sep(<<d1, d2, d3, sep, _rest::binary>>)
       when d1 in ?0..?9 and d2 in ?0..?9 and d3 in ?0..?9 and sep in '- ' do
    code = (d1 - ?0) * 100 + (d2 - ?0) * 10 + (d3 - ?0)
    {code, sep}
  end

  defp smtp_code_and_sep(_), do: {nil, nil}

  # =========================
  # SSL/TCP option helpers
  # =========================

  defp base_ssl_opts(nil, user_ssl_opts, verify) do
    # No SNI available (likely IP literal) — don't add SNI; still allow verification if caller supplies hostname via opts
    base_ssl_opts_with_sni(nil, user_ssl_opts, verify)
  end

  defp base_ssl_opts(sni_host, user_ssl_opts, verify) do
    base_ssl_opts_with_sni(sni_host, user_ssl_opts, verify)
  end

  defp base_ssl_opts_with_sni(sni_host, user_ssl_opts, verify) do
    base = [
      {:active, false},
      {:reuse_sessions, false},
      {:versions, [:"tlsv1.3", :"tlsv1.2"]}
    ]

    with_sni =
      if sni_host && !Keyword.has_key?(user_ssl_opts, :server_name_indication) do
        [{:server_name_indication, sni_host} | base]
      else
        base
      end

    with_verify =
      if verify do
        cacerts =
          cond do
            Keyword.has_key?(user_ssl_opts, :cacerts) or
                Keyword.has_key?(user_ssl_opts, :cacertfile) ->
              :skip

            function_exported?(:public_key, :cacerts_get, 0) ->
              case :public_key.cacerts_get() do
                certs when is_list(certs) -> certs
                _ -> []
              end

            true ->
              []
          end

        verify_opts =
          [
            {:verify, :verify_peer},
            {:depth, 5}
          ] ++
            if is_list(cacerts) and cacerts != [] and cacerts != :skip,
              do: [{:cacerts, cacerts}],
              else: []

        verify_opts ++ with_sni
      else
        with_sni
      end

    # Caller-supplied ssl_opts should take precedence, so merge base first, then user opts
    Keyword.merge(with_verify, user_ssl_opts)
  end

  defp safe_close_tcp(sock) do
    try do
      :gen_tcp.close(sock)
    catch
      _, _ -> :ok
    end
  end

  # =========================
  # Host normalization
  # =========================

  defp normalize_host({_, _, _, _} = ip4), do: ip4
  defp normalize_host({_, _, _, _, _, _, _, _} = ip6), do: ip6
  defp normalize_host(host) when is_binary(host), do: String.to_charlist(host)
  defp normalize_host(host) when is_list(host), do: host

  defp normalize_host_and_sni({_, _, _, _} = ip4), do: {ip4, nil}
  defp normalize_host_and_sni({_, _, _, _, _, _, _, _} = ip6), do: {ip6, nil}

  defp normalize_host_and_sni(host) when is_binary(host) do
    cl = String.to_charlist(host)
    {cl, cl}
  end

  defp normalize_host_and_sni(host) when is_list(host) do
    {host, host}
  end
end
