defmodule MessagingGateway.Dispatch.WorkerTest do
  use MessagingGateway.DataCase, async: true
  use Oban.Testing, repo: MessagingGateway.Repo

  alias MessagingGateway.Accounts.Tenant
  alias MessagingGateway.Dispatch.Worker
  alias MessagingGateway.Messaging
  alias MessagingGateway.Messaging.Message

  setup do
    t = tenant_fixture(%{balance: 10_000})
    ch = channel_fixture(t)
    %{t: t, ch: ch, m: message_fixture(t, ch)}
  end

  test "queued message is delivered and marked sent", %{m: m} do
    assert :ok = perform_job(Worker, %{"message_id" => m.id})
    assert Repo.get!(Message, m.id).status == "sent"
  end

  test "messages no longer queued are left alone", %{m: m} do
    {:ok, :updated, _} = Messaging.apply_status_update(m.id, "failed", "x")
    assert :ok = perform_job(Worker, %{"message_id" => m.id})
    assert Repo.get!(Message, m.id).status == "failed"
  end

  test "vendor failure before the last attempt asks Oban to retry", %{t: t, ch: ch} do
    m = message_fixture(t, ch, %{recipient: "+9991234567"})
    assert {:error, :vendor_error} = perform_job(Worker, %{"message_id" => m.id}, attempt: 1)
    assert Repo.get!(Message, m.id).status == "queued"
  end

  test "vendor failure on the last attempt fails the message and refunds", %{t: t, ch: ch} do
    m = message_fixture(t, ch, %{recipient: "+9991234567", cost: 500})
    assert :ok = perform_job(Worker, %{"message_id" => m.id}, attempt: 3)
    assert %{status: "failed", failure_reason: "dispatch_failed"} = Repo.get!(Message, m.id)
    assert Repo.get!(Tenant, t.id).balance == 10_500
  end

  test "unknown or malformed ids cancel the job" do
    for id <- [Ecto.UUID.generate(), "nope"],
        do: assert({:cancel, :message_not_found} = perform_job(Worker, %{"message_id" => id}))
  end

  test "job args carry only the message id" do
    assert Worker.new(%{"message_id" => "abc"}).changes.args == %{"message_id" => "abc"}
  end
end
