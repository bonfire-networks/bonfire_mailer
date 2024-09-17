defmodule Bonfire.Mailer.Render do
  alias Bonfire.Common.Utils
  use Arrows
  import Untangle

  def new_templated(mod, assigns, opts \\ []) do
    Bonfire.Mailer.new()
    |> templated(mod, assigns, opts)
  end

  def templated(%{} = email, mod, assigns, opts \\ []) do
    template = opts[:template] || filename_for_module_template(mod)

    email
    |> html_body("mjml", template, mod, assigns, opts)
    |> text_body("text", template, mod, assigns, opts)
  end

  defp html_body(email, "mjml" = format, template, mod, assigns, opts) do
    render_to_string(mod, template, format, assigns)
    |> maybe_with_layout(format, email, ..., assigns, opts[:layout])
    |> to_binary()
    |> mjml_to_html()
    |> Bonfire.Mailer.html_body(email, ...)
  end

  defp text_body(email, format, template, mod, assigns, opts) do
    render_to_string(mod, template, format, assigns)
    |> maybe_with_layout(format, email, ..., assigns, opts[:layout])
    |> to_binary()
    |> Bonfire.Mailer.text_body(email, ...)
  end

  def maybe_with_layout(_format, _email, inner_content, assigns, nil), do: inner_content

  def maybe_with_layout(format, email, inner_content, assigns, layout) do
    assigns =
      Map.merge(assigns, %{
        inner_content: inner_content
        # email: email
      })
      |> debug()
      |> render_to_string(layout, format, ...)
  end

  def render_to_string(mod, format, assigns) do
    render_to_string(mod, filename_for_module_template(mod), format, assigns)
  end

  #   def render_to_string(mod, template, format, assigns) do
  #     Phoenix.Template.render_to_string(mod, "#{template}_#{format}", format, assigns)
  #   end
  def render_to_string(mod, template, format, assigns) do
    case String.to_existing_atom("#{template}_#{format}") do
      nil ->
        nil

      template ->
        Utils.maybe_apply(mod, template, [assigns], fallback_return: "")
    end
  end

  defp to_binary(%Phoenix.LiveView.Rendered{} = rendered),
    do:
      rendered
      |> Phoenix.HTML.html_escape()
      |> Phoenix.HTML.safe_to_string()

  # |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()
  defp to_binary(rendered) when is_binary(rendered), do: rendered

  defp mjml_to_html(mjml_binary), do: with({:ok, html} <- Mjml.to_html(mjml_binary), do: html)

  defp filename_for_module_template(module) do
    module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
  end
end
