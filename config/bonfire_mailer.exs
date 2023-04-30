import Config

config :bonfire_mailer,
  reply_to: "noreply@bonfire.local",
  check_mx: true,
  check_format: true

config :bonfire_mailer, Bonfire.Mailer,
  # set what service you want to use to send emails, from these: https://github.com/thoughtbot/bamboo#available-adapters
  adapter: Bamboo.LocalAdapter
