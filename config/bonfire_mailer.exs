import Config

config :bonfire_mailer,
  from_address: "noreply@bonfire.local",
  check_mx: true,
  check_format: true

config :bonfire, Bonfire.Mailer,
  # set what service you want to use to send emails, from these: https://github.com/thoughtbot/bamboo#available-adapters
  adapter: Bamboo.LocalAdapter
