defmodule Bonfire.Mailer.RuntimeConfig do

  def config_module, do: true

  def config do
    import Config

    # send emails in prod and dev only config
    if config_env() != :test do

      mail_blackhole = fn var ->
        IO.puts(
          "WARNING: The environment variable #{var} was not set or was set incorrectly, mail will NOT be sent."
        )

        config :bonfire, Bonfire.Mailer, adapter: Bamboo.LocalAdapter
      end

      mail_mailgun = fn ->
        # API URI depends on whether you're registered with Mailgun in EU, US, etc (defaults to EU)
        base_uri = System.get_env("MAIL_BASE_URI", "https://api.eu.mailgun.net/v3")

        case System.get_env("MAIL_KEY") do
          nil ->
            mail_blackhole.("MAIL_KEY")

          key ->
            case System.get_env("MAIL_DOMAIN") do
              nil ->
                mail_blackhole.("MAIL_DOMAIN")

              domain ->
                case System.get_env("MAIL_FROM") do
                  nil ->
                    mail_blackhole.("MAIL_FROM")

                  from ->
                    IO.puts("Note: Transactional emails will be sent through Mailgun.")

                    config :bonfire, Bonfire.Mailer,
                      adapter: Bamboo.MailgunAdapter,
                      api_key: key,
                      base_uri: base_uri,
                      domain: domain,
                      reply_to: from
                end
            end
        end
      end

      mail_smtp = fn ->
        case System.get_env("MAIL_SERVER") do
          nil ->
            mail_blackhole.("MAIL_SERVER")

          server ->
            case System.get_env("MAIL_DOMAIN") do
              nil ->
                mail_blackhole.("MAIL_DOMAIN")

              domain ->
                case System.get_env("MAIL_USER") do
                  nil ->
                    mail_blackhole.("MAIL_USER")

                  user ->
                    case System.get_env("MAIL_PASSWORD") do
                      nil ->
                        mail_blackhole.("MAIL_PASSWORD")

                      password ->
                        case System.get_env("MAIL_FROM") do
                          nil ->
                            mail_blackhole.("MAIL_FROM")

                          from ->
                            IO.puts("Note: Transactional emails will be sent through SMTP.")

                            config :bonfire, Bonfire.Mailer,
                              adapter: Bamboo.SMTPAdapter,
                              server: server,
                              hostname: domain,
                              port: String.to_integer(System.get_env("MAIL_PORT", "587")),
                              username: user,
                              password: password,
                              tls: :always,
                              allowed_tls_versions: [:"tlsv1.2"],
                              ssl: false,
                              retries: 1,
                              auth: :always,
                              reply_to: from
                        end
                    end
                end
            end
        end
      end

      case System.get_env("MAIL_BACKEND") do
        "mailgun" -> mail_mailgun.()
        "smtp" -> mail_smtp.()
        _ -> mail_blackhole.("MAIL_BACKEND")
      end

    end

  end
end
