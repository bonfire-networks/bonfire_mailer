import Config

config :bonfire_mailer, Bonfire.Mailer.Swoosh, adapter: Swoosh.Adapters.Test

config :bonfire_mailer, Bonfire.Mailer.Bamboo, adapter: Bamboo.TestAdapter
