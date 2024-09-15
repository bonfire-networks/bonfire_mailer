defmodule Bonfire.Mailer.BambooTest do
  # Use the module
  use ExUnit.Case, async: true
  use Untangle

  use Bamboo.Test

  setup do
    Process.put([:bonfire_mailer, Bonfire.Mailer, :mailer_backend], Bonfire.Mailer.Bamboo)
    on_exit(fn -> Process.delete([:bonfire_mailer, Bonfire.Mailer, :mailer_backend]) end)
  end

  test "standard integration works" do
    debug(Bonfire.Mailer.RuntimeConfig.mailer())

    debug(
      Bonfire.Common.Config.get_for_process([:bonfire_mailer, Bonfire.Mailer, :mailer_backend])
    )

    {:ok, email} = Bonfire.Mailer.send_app_feedback("Hello, Avengers!", "test", mode: :now)

    # assert a specific email was sent
    assert_delivered_email(email)
  end

  test "async integration works" do
    debug(Bonfire.Mailer.RuntimeConfig.mailer())

    debug(
      Bonfire.Common.Config.get_for_process([:bonfire_mailer, Bonfire.Mailer, :mailer_backend])
    )

    {:ok, email} = Bonfire.Mailer.send_app_feedback("Hello, Avengers!", "test", mode: :async)

    # assert a specific email was sent
    assert_delivered_email(email)
  end
end
