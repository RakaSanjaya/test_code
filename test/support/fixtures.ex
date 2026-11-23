defmodule MessagingGateway.Fixtures do
  @moduledoc "Test data builders. Inserts go straight to the Repo (no billing side effects)."

  alias MessagingGateway.Accounts.Tenant
  alias MessagingGateway.Messaging.{Channel, Message, Template}
  alias MessagingGateway.Repo

  defp uniq, do: System.unique_integer([:positive])

  def tenant_fixture(attrs \\ %{}) do
    defaults = %{name: "Tenant #{uniq()}", balance: 10_000, status: "active"}

    %Tenant{}
    |> Tenant.changeset(Enum.into(attrs, defaults))
    |> Repo.insert!()
  end

  def channel_fixture(%Tenant{} = tenant, attrs \\ %{}) do
    defaults = %{
      tenant_id: tenant.id,
      type: "whatsapp",
      name: "Channel #{uniq()}",
      default_category: "utility",
      active: true
    }

    %Channel{}
    |> Channel.changeset(Enum.into(attrs, defaults))
    |> Repo.insert!()
  end

  def template_fixture(%Tenant{} = tenant, attrs \\ %{}) do
    defaults = %{
      tenant_id: tenant.id,
      code: "otp_login_v1",
      category: "authentication",
      body_pattern: "Kode OTP Anda adalah {{1}}",
      status: "approved"
    }

    %Template{}
    |> Template.changeset(Enum.into(attrs, defaults))
    |> Repo.insert!()
  end

  @doc "Inserts a message directly, WITHOUT debiting the tenant."
  def message_fixture(%Tenant{} = tenant, %Channel{} = channel, attrs \\ %{}) do
    defaults = %{
      tenant_id: tenant.id,
      channel_id: channel.id,
      recipient: "+6281234567890",
      content: "Halo",
      category: "utility",
      cost: 500,
      status: "queued",
      request_fingerprint: String.duplicate("0", 64),
      metadata: %{}
    }

    %Message{}
    |> Message.create_changeset(Enum.into(attrs, defaults))
    |> Repo.insert!()
  end
end
