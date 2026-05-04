defmodule Bonfire.Mailer.RuntimeConfig do
  @behaviour Bonfire.Common.ConfigModule
  import Config
  use Bonfire.Common.Config
  import Untangle
  def config_module, do: true

  @yes? ~w(true yes 1)
  @no? ~w(false no none 0)

  def mail_blackhole(var) do
    warn(
      var,
      "An environment variable was not set or was set incorrectly, mail will attempt being sent directly to the recipient's SMTP server (make sure your instance domain has SPF, DKIM, etc configured correctly)"
    )

    config :bonfire_mailer, Bonfire.Mailer, mailer_behaviour: Bonfire.Mailer.Swoosh

    # see https://hexdocs.pm/swoosh/Swoosh.Adapters.Mua.html
    config :bonfire_mailer, Bonfire.Mailer.Swoosh,
      adapter: Swoosh.Adapters.Mua,
      ssl: Bonfire.Common.HTTP.Connection.default_ssl_options()

    config :bonfire_mailer, Bonfire.Mailer, timeout: 1000
  end

  def mailer do
    Bonfire.Common.Config.get([Bonfire.Mailer, :mailer_behaviour]) || Bonfire.Mailer.Swoosh
  end

  def config do
    import Config

    # to cache the decoded SSL certificates
    config :mua, persistent_term: true

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
          swoosh_service(Swoosh.Adapters.Mailgun,
            base_uri: System.get_env("MAIL_BASE_URI", "https://api.eu.mailgun.net/v3")
          )

        # note: API base URI depends on whether you're registered with Mailgun in EU, US, etc (defaults to EU)

        "mandrill" ->
          swoosh_service(Swoosh.Adapters.Mandrill)

        "mailjet" ->
          secret_key = System.fetch_env!("MAIL_PRIVATE_KEY")

          swoosh_service(Swoosh.Adapters.Mailjet,
            api_private_key: secret_key,
            secret: secret_key
          )

        "mailtrap" ->
          swoosh_service(Swoosh.Adapters.Mailtrap)

        "mailpace" ->
          swoosh_service(Swoosh.Adapters.MailPace)

        "msgraph" ->
          swoosh_service(Swoosh.Adapters.MsGraph, auth: System.fetch_env!("MAIL_PRIVATE_KEY"))

        "postal" ->
          swoosh_service(Swoosh.Adapters.Postal,
            base_uri: System.fetch_env!("MAIL_BASE_URI")
          )

        "postmark" ->
          swoosh_service(Swoosh.Adapters.Postmark)

        "scaleway" ->
          swoosh_service(Swoosh.Adapters.Scaleway,
            project_id: System.fetch_env!("MAIL_PROJECT_ID"),
            secret_key: System.fetch_env!("MAIL_PRIVATE_KEY")
          )

        "socketlabs" ->
          swoosh_service(Swoosh.Adapters.SocketLabs,
            server_id: System.fetch_env!("MAIL_SERVER"),
            api_key: System.fetch_env!("MAIL_PRIVATE_KEY")
          )

        "SMTP2GO" ->
          swoosh_service(Swoosh.Adapters.SMTP2GO)

        "sendgrid" ->
          swoosh_service(Swoosh.Adapters.Sendgrid)

        "sparkpost" ->
          swoosh_service(Swoosh.Adapters.SparkPost,
            endpoint: System.get_env("MAIL_BASE_URI", "https://api.eu.sparkpost.com")
          )

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
                  config :bonfire_mailer, Bonfire.Mailer, mailer_behaviour: Bonfire.Mailer.Swoosh

                  if System.get_env("UPLOADS_S3_ACCESS_KEY_ID") &&
                       System.get_env("UPLOADS_S3_SECRET_ACCESS_KEY") &&
                       (!System.get_env("MAIL_KEY") || !System.get_env("MAIL_PRIVATE_KEY")) do
                    # send using same credentials as ex_aws (eg. configure for file uploads)
                    config :bonfire_mailer, Bonfire.Mailer.Swoosh,
                      adapter: Swoosh.Adapters.AmazonSES
                  else
                    region =
                      System.get_env("MAIL_REGION") || System.get_env("UPLOADS_S3_REGION") ||
                        "eu-west-1"

                    config :bonfire_mailer, Bonfire.Mailer.Swoosh,
                      adapter: Swoosh.Adapters.AmazonSES,
                      region: region,
                      access_key: key_id,
                      secret: private_key
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
                qmail: System.get_env("MAIL_QMAIL") in @yes?
          end

        "smtp" ->
          case System.get_env("MAIL_SERVER") do
            nil ->
              mail_blackhole("MAIL_SERVER")

            server ->
              case System.get_env("MAIL_DOMAIN") || System.get_env("HOSTNAME") do
                nil ->
                  mail_blackhole("MAIL_DOMAIN or HOSTNAME")

                _domain ->
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

                            _from ->
                              IO.puts("Note: Transactional emails will be sent through SMTP.")

                              port = String.to_integer(System.get_env("MAIL_PORT", "587"))

                              config :bonfire_mailer, Bonfire.Mailer.Swoosh,
                                adapter: Swoosh.Adapters.Mua,
                                relay: server,
                                port: port,
                                auth: [username: user, password: password],
                                protocol:
                                  if(System.get_env("MAIL_SSL", "true") in @no?,
                                    do: :tcp,
                                    else: :ssl
                                  ),
                                ssl: [
                                  verify: :verify_peer,
                                  # Some servers don't support TLS v1.3 yet so we disable it for compatibility
                                  versions: [:tlsv1, :"tlsv1.1", :"tlsv1.2"]
                                ]
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

              _from ->
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
end
