defmodule Bonfire.Mailer.RuntimeConfig do
  @behaviour Bonfire.Common.ConfigModule
  import Config
  import Untangle
  def config_module, do: true

  def mail_blackhole(var) do
    warn(
      var,
      "An environment variable was not set or was set incorrectly, mail will attempt being sent directly to the recipient's SMTP server (make sure your instance domain has SPF, DKIM, etc configured correctly)"
    )

    config :bonfire_mailer, Bonfire.Mailer, mailer_behaviour: Bonfire.Mailer.Swoosh

    # see https://hexdocs.pm/swoosh/Swoosh.Adapters.Mua.html
    config :bonfire_mailer, Bonfire.Mailer.Swoosh, adapter: Swoosh.Adapters.Mua
    # just in case
    config :bonfire_mailer, Bonfire.Mailer.Bamboo, adapter: Bamboo.LocalAdapter
  end

  def mailer do
    Bonfire.Common.Config.get([Bonfire.Mailer, :mailer_behaviour]) || Bonfire.Mailer.Swoosh
  end

  def config do
    import Config

    # send emails in prod and dev only config
    if config_env() != :test do
      case System.get_env("MAIL_BACKEND") do
        "brevo" ->
          swoosh_service(Swoosh.Adapters.Brevo)

        "dyn" ->
          swoosh_service(Swoosh.Adapters.Dyn)

        "gmail" ->
          swoosh_service(Swoosh.Adapters.Gmail)

        "mailgun" ->
          any_service(Swoosh.Adapters.Mailgun, Bamboo.MailgunAdapter,
            base_uri: System.get_env("MAIL_BASE_URI", "https://api.eu.mailgun.net/v3")
          )

        # note: API base URI depends on whether you're registered with Mailgun in EU, US, etc (defaults to EU)

        "mandrill" ->
          any_service(Swoosh.Adapters.Mandrill, Bamboo.MandrillAdapter)

        "mailjet" ->
          secret_key = System.get_env!("MAIL_PRIVATE_KEY")

          any_service(Swoosh.Adapters.Mailjet, Bamboo.MailjetAdapter,
            api_private_key: secret_key,
            secret: secret_key
          )

        "mailtrap" ->
          swoosh_service(Swoosh.Adapters.Mailtrap)

        "mailpace" ->
          swoosh_service(Swoosh.Adapters.MailPace)

        "msgraph" ->
          swoosh_service(Swoosh.Adapters.MsGraph, auth: System.get_env!("MAIL_PRIVATE_KEY"))

        "postal" ->
          swoosh_service(Swoosh.Adapters.Postal,
            base_uri: System.get_env!("MAIL_BASE_URI")
          )

        "postmark" ->
          any_service(Swoosh.Adapters.Postmark, Bamboo.PostmarkAdapter)

        "campaign_monitor" ->
          bamboo_service(Bamboo.CampaignMonitorAdapter)

        "scaleway" ->
          swoosh_service(Swoosh.Adapters.Scaleway,
            project_id: System.get_env!("MAIL_PROJECT_ID"),
            secret_key: System.get_env!("MAIL_PRIVATE_KEY")
          )

        "sendcloud" ->
          bamboo_service(Bamboo.SendcloudAdapter, api_user: System.get_env!("MAIL_USER"))

        "socketlabs" ->
          swoosh_service(Swoosh.Adapters.SocketLabs,
            server_id: System.get_env!("MAIL_SERVER"),
            api_key: System.get_env!("MAIL_PRIVATE_KEY")
          )

        "SMTP2GO" ->
          swoosh_service(Swoosh.Adapters.SMTP2GO)

        "sendgrid" ->
          any_service(Swoosh.Adapters.Sendgrid, Bamboo.SendGridAdapter)

        "sparkpost" ->
          endpoint = System.get_env("MAIL_BASE_URI", "https://api.eu.sparkpost.com")
          any_service(Swoosh.Adapters.SparkPost, Bamboo.SparkPostAdapter, endpoint: endpoint)

          config :bamboo,
            sparkpost_base_uri: endpoint

        "zepto" ->
          swoosh_service(Swoosh.Adapters.ZeptoMail)

        "aws" ->
          IO.puts("Note: Transactional emails will be sent through AWS SES.")

          case System.get_env("MAIL_KEY") || System.get_env("UPLOADS_S3_ACCESS_KEY_ID") do
            nil ->
              mail_blackhole("MAIL_KEY or UPLOADS_S3_ACCESS_KEY_ID")

            key_id ->
              case System.get_env("MAIL_PRIVATE_KEY") ||
                     System.get_env("UPLOADS_S3_SECRET_ACCESS_KEY") do
                nil ->
                  mail_blackhole("MAIL_PRIVATE_KEY or UPLOADS_S3_SECRET_ACCESS_KEY")

                private_key ->
                  if System.get_env("UPLOADS_S3_ACCESS_KEY_ID") &&
                       System.get_env("UPLOADS_S3_SECRET_ACCESS_KEY") &&
                       (!System.get_env("MAIL_KEY") || !System.get_env("MAIL_PRIVATE_KEY")) do
                    config :bonfire_mailer, Bonfire.Mailer,
                      mailer_behaviour: Bonfire.Mailer.Swoosh

                    config :bonfire_mailer, Bonfire.Swoosh,
                      # send using same credentials as ex_aws (eg. configure for file uploads)
                      adapter: Swoosh.Adapters.AmazonSES
                  else
                    region =
                      System.get_env("MAIL_REGION") || System.get_env("UPLOADS_S3_REGION") ||
                        "eu-west-1"

                    if System.get_env("MAIL_LIB") != "bamboo" do
                      config :bonfire_mailer, Bonfire.Mailer,
                        mailer_behaviour: Bonfire.Mailer.Swoosh

                      config :bonfire_mailer, Bonfire.Swoosh,
                        adapter: Swoosh.Adapters.AmazonSES,
                        region: region,
                        access_key: key_id,
                        secret: private_key
                    else
                      config :bonfire_mailer, Bonfire.Mailer,
                        mailer_behaviour: Bonfire.Mailer.Bamboo

                      config :bonfire_mailer, Bonfire.Mailer.Bamboo,
                        adapter: Bamboo.SesAdapter,
                        ex_aws: [
                          json_codec: Jason,
                          #  falls back to use same config as used by bonfire_files
                          region: region,
                          access_key_id: key_id,
                          secret_access_key: private_key,
                          # optionally can use session token
                          security_token: System.get_env("MAIL_SESSION_TOKEN")
                        ]
                    end
                  end
              end
          end

        "sendmail" ->
          case System.get_env("MAIL_SERVER", "/usr/bin/sendmail") do
            nil ->
              mail_blackhole("MAIL_SERVER")

            path ->
              config :bonfire_mailer, Bonfire.Mailer.Swoosh,
                adapter: Swoosh.Adapters.Sendmail,
                cmd_path: path,
                cmd_args: System.get_env("MAIL_ARGS", "-N delay,failure,success"),
                qmail: System.get_env("MAIL_QMAIL") == "true"
          end

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

                              port = String.to_integer(System.get_env("MAIL_PORT", "587"))

                              if System.get_env("MAIL_LIB") != "bamboo" do
                                config :sample, Sample.Mailer,
                                  adapter: Swoosh.Adapters.Mua,
                                  relay: server,
                                  port: port,
                                  auth: [username: user, password: password]
                              else
                                config :bonfire_mailer, Bonfire.Mailer,
                                  mailer_behaviour: Bonfire.Mailer.Bamboo

                                config :bonfire_mailer, Bonfire.Mailer.Bamboo,
                                  adapter: Bamboo.SMTPAdapter,
                                  server: server,
                                  hostname: domain,
                                  port: port,
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
                                     end)
                              end
                          end
                      end
                  end
              end
          end

        _ ->
          mail_blackhole("MAIL_BACKEND")
      end
    end

    config :bonfire_mailer, Bonfire.Mailer,
      feedback_to: System.get_env("BONFIRE_APP_FEEDBACK_TO"),
      reply_to: System.get_env("MAIL_FROM")

    config :swoosh, :api_client, Swoosh.ApiClient.Req
  end

  def bamboo_service(adapter, extra \\ []) do
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

                config :bonfire_mailer, Bonfire.Mailer, mailer_behaviour: Bonfire.Mailer.Bamboo

                config :bonfire_mailer, Bonfire.Mailer.Bamboo,
                  adapter: adapter,
                  domain: domain,
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

  def swoosh_service(adapter, extra \\ []) do
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

                config :bonfire_mailer, Bonfire.Mailer, mailer_behaviour: Bonfire.Mailer.Swoosh

                config :bonfire_mailer, Bonfire.Mailer.Swoosh,
                  adapter: adapter,
                  domain: domain,
                  api_key: key,
                  access_token: key,
                  api_user: extra[:api_user],
                  project_id: extra[:project_id],
                  server_id: extra[:server_id],
                  endpoint: extra[:endpoint],
                  auth: extra[:auth],
                  secret: extra[:secret],
                  secret_key: extra[:secret_key],
                  api_private_key: extra[:api_private_key],
                  base_uri: extra[:base_uri],
                  base_url: extra[:base_uri]
            end
        end
    end
  end

  defp any_service(swoosh, bamboo, extra \\ []) do
    if System.get_env("MAIL_LIB") == "bamboo" do
      bamboo_service(bamboo, extra)
    else
      #  default
      swoosh_service(swoosh, extra)
    end
  end
end
