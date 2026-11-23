defmodule MessagingGateway.AccountsTest do
  use MessagingGateway.DataCase, async: true

  alias MessagingGateway.Accounts
  alias MessagingGateway.Accounts.{ApiKey, Secret, Tenant}

  test "generated keys are prefixed, long and unique" do
    assert "sk_" <> rest = s = Secret.generate_secret()
    assert byte_size(rest) == 43
    refute s == Secret.generate_secret()
    assert "ck_" <> ck = Secret.generate_client_key()
    assert byte_size(ck) == 24
  end

  test "hash/2 is deterministic lowercase hex and depends on the pepper" do
    h = Secret.hash("sk_abc", "pepper-a")
    assert h =~ ~r/\A[0-9a-f]{64}\z/
    assert h == Secret.hash("sk_abc", "pepper-a")
    refute h == Secret.hash("sk_abc", "pepper-b")
  end

  test "verify/2" do
    h = Secret.hash("sk_abc")
    assert Secret.verify("sk_abc", h)
    refute Secret.verify("sk_abd", h)
    refute Secret.verify("sk_abc", "short")
  end

  test "create_api_key/2 returns the plaintext once and stores only the hash" do
    {:ok, key, secret} = Accounts.create_api_key(tenant_fixture(), %{scopes: ["messages:read"]})
    assert key.secret_hash == Secret.hash(secret)
    %{rows: rows} = Repo.query!("SELECT * FROM api_keys WHERE id = $1", [Ecto.UUID.dump!(key.id)])
    refute secret in List.flatten(rows)
  end

  test "create_api_key/2 rejects unknown scopes" do
    assert {:error, %Ecto.Changeset{}} =
             Accounts.create_api_key(tenant_fixture(), %{scopes: ["admin"]})
  end

  describe "authenticate/2" do
    setup do
      t = tenant_fixture()
      {key, secret} = api_key_fixture(t)
      %{t: t, key: key, secret: secret}
    end

    test "valid credentials return the key with its tenant", %{t: t, key: key, secret: s} do
      assert {:ok, %ApiKey{id: id, tenant: %Tenant{id: tid}}} =
               Accounts.authenticate(key.client_key, s)

      assert id == key.id and tid == t.id
    end

    test "every bad credential is :unauthorized", %{key: key, secret: s} do
      {_other, other_secret} = api_key_fixture(tenant_fixture())

      for {ck, sec} <- [
            {key.client_key, "sk_wrong"},
            {"ck_unknown", s},
            {key.client_key, other_secret},
            {key.client_key, String.duplicate("a", 10_000)},
            {nil, s},
            {key.client_key, ""}
          ] do
        assert Accounts.authenticate(ck, sec) == {:error, :unauthorized}
      end
    end

    test "inactive key is :unauthorized" do
      {key, s} = api_key_fixture(tenant_fixture(), ["messages:read"], %{active: false})
      assert Accounts.authenticate(key.client_key, s) == {:error, :unauthorized}
    end

    test "suspension is only revealed to the holder of the correct secret" do
      {key, s} = api_key_fixture(tenant_fixture(%{status: "suspended"}))
      assert Accounts.authenticate(key.client_key, s) == {:error, :tenant_suspended}
      assert Accounts.authenticate(key.client_key, "sk_wrong") == {:error, :unauthorized}
    end
  end
end
