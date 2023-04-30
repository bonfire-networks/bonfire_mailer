defmodule Bonfire.Mailer.RuntimeConfig do
  @behaviour Bonfire.Common.ConfigModule
  import Config
  def config_module, do: true

  def mail_blackhole(var) do
    IO.puts(
      "WARNING: The environment variable #{var} was not set or was set incorrectly, mail will NOT be sent."
    )

    config :bonfire_mailer, Bonfire.Mailer, adapter: Bamboo.LocalAdapter
  end

  def mail_service(adapter, extra \\ []) do
    case System.get_env("MAIL_KEY") do
      nil ->
        mail_blackhole("MAIL_KEY")

      key ->
        case System.get_env("MAIL_DOMAIN") || System.get_env("HOSTNAME") do
          nil ->
            mail_blackhole("MAIL_DOMAIN or HOSTNAME")

          domain ->
            case System.get_env("MAIL_FROM") do
              nil ->
                mail_blackhole("MAIL_FROM")

              from ->
                IO.puts("Note: Transactional emails will be sent through #{adapter}.")

                config :bonfire_mailer, Bonfire.Mailer,
                  adapter: adapter,
                  domain: domain,
                  reply_to: from,
                  api_key: key,
                  api_user: extra[:api_user],
                  api_private_key: extra[:api_private_key],
                  base_uri: extra[:base_uri],
                  hackney_opts: [
                    recv_timeout: :timer.minutes(1)
                  ]
            end
        end
    end
  end

  def config do
    import Config

    # send emails in prod and dev only config
    if config_env() != :test do
      case System.get_env("MAIL_BACKEND") do
        "mailgun" ->
          mail_service(Bamboo.MailgunAdapter,
            base_uri: System.get_env("MAIL_BASE_URI", "https://api.eu.mailgun.net/v3")
          )

        # note: API base URI depends on whether you're registered with Mailgun in EU, US, etc (defaults to EU)

        "mandrill" ->
          mail_service(Bamboo.MandrillAdapter)

        "sendgrid" ->
          mail_service(Bamboo.SendGridAdapter)

        "mailjet" ->
          mail_service(Bamboo.MailjetAdapter, api_private_key: System.get_env("MAIL_PRIVATE_KEY"))

        "postmark" ->
          mail_service(Bamboo.PostmarkAdapter)

        "campaign_monitor" ->
          mail_service(Bamboo.CampaignMonitorAdapter)

        "sendcloud" ->
          mail_service(Bamboo.SendcloudAdapter, api_user: System.get_env("MAIL_API_USER"))

        "sparkpost" ->
          mail_service(Bamboo.SparkPostAdapter)

          config :bamboo,
            sparkpost_base_uri: System.get_env("MAIL_BASE_URI", "https://api.eu.sparkpost.com")

        "smtp" ->
          case System.get_env("MAIL_SERVER") do
            nil ->
              mail_blackhole("MAIL_SERVER")

            server ->
              case System.get_env("MAIL_DOMAIN") || System.get_env("HOSTNAME") do
                nil ->
                  mail_blackhole("MAIL_DOMAIN or HOSTNAME")

                domain ->
                  case System.get_env("MAIL_USER") do
                    nil ->
                      mail_blackhole("MAIL_USER")

                    user ->
                      case System.get_env("MAIL_PASSWORD") do
                        nil ->
                          mail_blackhole("MAIL_PASSWORD")

                        password ->
                          case System.get_env("MAIL_FROM") do
                            nil ->
                              mail_blackhole("MAIL_FROM")

                            from ->
                              IO.puts("Note: Transactional emails will be sent through SMTP.")

                              config :bonfire_mailer, Bonfire.Mailer,
                                adapter: Bamboo.SMTPAdapter,
                                server: server,
                                hostname: domain,
                                port: String.to_integer(System.get_env("MAIL_PORT", "587")),
                                username: user,
                                password: password,
                                tls:
                                  (case System.get_env("MAIL_TLS") do
                                     "1" -> :always
                                     "0" -> :never
                                     _ -> :if_available
                                   end),
                                allowed_tls_versions: [:"tlsv1.2"],
                                ssl: System.get_env("MAIL_SSL", "false") not in ["false", "0"],
                                retries: String.to_integer(System.get_env("MAIL_RETRIES", "1")),
                                auth:
                                  (case System.get_env("MAIL_SMTP_AUTH") do
                                     "1" -> :always
                                     _ -> :if_available
                                   end),
                                reply_to: from
                          end
                      end
                  end
              end
          end

        "aws" ->
          IO.puts("Note: Transactional emails will be sent through AWS SES.")

          config :bonfire_mailer, Bonfire.Mailer,
            adapter: Bamboo.SesAdapter,
            ex_aws: [
              json_codec: Jason,
              #  falls back to use same config as used by bonfire_files
              region:
                System.get_env("MAIL_REGION") || System.get_env("UPLOADS_S3_REGION") ||
                  "eu-west-1",
              access_key_id:
                System.get_env("MAIL_KEY") || System.get_env("UPLOADS_S3_ACCESS_KEY_ID"),
              secret_access_key:
                System.get_env("MAIL_PRIVATE_KEY") ||
                  System.get_env("UPLOADS_S3_SECRET_ACCESS_KEY"),
              # optionally can use session token
              security_token: System.get_env("MAIL_SESSION_TOKEN")
            ]

        _ ->
          mail_blackhole("MAIL_BACKEND")
      end
    end

    config :bonfire_mailer, Bonfire.Mailer, feedback_to: System.get_env("BONFIRE_APP_FEEDBACK_TO")
  end
end
