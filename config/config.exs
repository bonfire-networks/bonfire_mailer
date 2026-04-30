import Config

# Register `.mjml.eex` as a Phoenix template extension so views can render
# MJML with EEx interpolation. The rendered MJML is then converted to HTML
# by the calling code via `Mjml.to_html/1`.
config :phoenix, :template_engines, mjml: Phoenix.Template.EExEngine

import_config "bonfire_mailer.exs"

import_config "#{env}.exs"
