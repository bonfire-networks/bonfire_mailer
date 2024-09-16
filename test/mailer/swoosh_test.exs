defmodule Bonfire.Mailer.SwooshTest do
  # Use the module
  use ExUnit.Case, async: true
  use Untangle

  import Swoosh.TestAssertions

  setup do
    Process.put([:bonfire_mailer, Bonfire.Mailer, :mailer_behaviour], Bonfire.Mailer.Swoosh)
    on_exit(fn -> Process.delete([:bonfire_mailer, Bonfire.Mailer, :mailer_behaviour]) end)
  end

  test "standard integration works" do
    debug(Bonfire.Mailer.RuntimeConfig.mailer())

    debug(
      Bonfire.Common.Config.get_for_process([:bonfire_mailer, Bonfire.Mailer, :mailer_behaviour])
    )

    {:ok, email} = Bonfire.Mailer.send_app_feedback("Hello, Avengers!", "test", mode: :now)

    # assert a specific email was sent
    # assert_email_sent(email)

    # assert an email with specific field(s) was sent
    assert_email_sent(subject: "test - bonfire Hello, Avengers!")

    # assert an email that satisfies a condition
    # assert_email_sent(fn email ->
    # assert length(email.to) == 2
    # end)
  end

  #  how to wait for the async to be done before asserting?
  @tag :todo
  test "async integration works" do
    debug(Bonfire.Mailer.RuntimeConfig.mailer())

    debug(
      Bonfire.Common.Config.get_for_process([:bonfire_mailer, Bonfire.Mailer, :mailer_behaviour])
    )

    {:ok, email} = Bonfire.Mailer.send_app_feedback("Hello, Avengers!", "test", mode: :async)

    # assert an email with specific field(s) was sent
    assert_email_sent(subject: "test - bonfire Hello, Avengers!")
  end
end
