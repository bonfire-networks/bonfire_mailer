defmodule Bonfire.Mailer.Render do
  alias Bonfire.Common.Utils
  alias Bonfire.Common.Types
  alias Bonfire.Common.Config
  use Arrows
  import Untangle

  def default_layout, do: Config.get([__MODULE__, :default_layout], Bonfire.UI.Common.Email.Basic)

  def new_templated(mod, assigns, opts \\ []) do
    Bonfire.Mailer.new()
    |> templated(mod, assigns, opts)
  end

  def templated(%{} = email, mod, assigns, opts \\ []) do
    template = opts[:template] || filename_for_module_template(mod)
    layout = opts[:layout] || default_layout()

    email
    |> Bonfire.Mailer.html_body(render_templated("mjml", mod, assigns, template, layout, opts))
    |> Bonfire.Mailer.text_body(render_templated("text", template, mod, assigns, opts))
  end

  # TODO: put the following functions somewhere else?

  def render_templated(format, mod, assigns, template \\ nil, layout \\ nil, opts \\ [])

  def render_templated("mjml" = format, mod, assigns, template, layout, opts) do
    case render_to_string(mod, template || filename_for_module_template(mod), format, assigns) do
      nil ->
        nil

      binary ->
        maybe_with_layout(format, binary, assigns, layout)
        |> to_binary()
        |> mjml_to_html()
    end
  end

  def render_templated(format, mod, assigns, template, layout, opts) do
    case render_to_string(mod, template || filename_for_module_template(mod), format, assigns) do
      nil ->
        nil

      binary ->
        maybe_with_layout(format, binary, assigns, layout)
        |> to_binary()
    end
  end

  def maybe_with_layout(_format, inner_content, assigns, nil), do: inner_content

  def maybe_with_layout(format, inner_content, assigns, layout) do
    assigns =
      Map.merge(assigns, %{
        inner_content: inner_content
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
    case Types.maybe_to_atom!("#{template}_#{format}") do
      nil ->
        nil

      template ->
        Utils.maybe_apply(mod, template, [assigns], fallback_return: "")
    end
  end

  defp to_binary(%struct{} = rendered) when struct == Phoenix.LiveView.Rendered,
    do:
      rendered
      |> Phoenix.HTML.html_escape()
      |> Phoenix.HTML.safe_to_string()

  # |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()
  defp to_binary(rendered) when is_binary(rendered), do: rendered
  defp to_binary(_), do: ""

  defp mjml_to_html(mjml_binary), do: with({:ok, html} <- Mjml.to_html(mjml_binary), do: html)

  defp filename_for_module_template(module) do
    module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
  end
end
