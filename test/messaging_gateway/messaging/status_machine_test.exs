defmodule MessagingGateway.Messaging.StatusMachineTest do
  use ExUnit.Case, async: true

  alias MessagingGateway.Messaging.StatusMachine

  test "allowed, no-op and invalid transitions" do
    for {f, t} <- [
          {"queued", "sent"},
          {"queued", "failed"},
          {"sent", "delivered"},
          {"sent", "failed"}
        ],
        do: assert(StatusMachine.check(f, t) == :apply)

    for s <- ~w(queued sent delivered failed), do: assert(StatusMachine.check(s, s) == :noop)

    for {f, t} <- [
          {"queued", "delivered"},
          {"sent", "queued"},
          {"delivered", "failed"},
          {"delivered", "sent"},
          {"failed", "sent"},
          {"failed", "delivered"},
          {"queued", "bogus"}
        ],
        do: assert(StatusMachine.check(f, t) == :invalid)

    assert StatusMachine.final?("delivered") and StatusMachine.final?("failed")
    refute StatusMachine.final?("queued") or StatusMachine.final?("sent")
    assert StatusMachine.vendor_statuses() == ["sent", "delivered", "failed"]
  end
end
