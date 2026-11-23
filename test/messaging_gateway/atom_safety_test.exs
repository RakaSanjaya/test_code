defmodule MessagingGateway.AtomSafetyTest do
  use MessagingGatewayWeb.ConnCase, async: false

  test "hostile keys and enum values never mint atoms" do
    t = tenant_fixture()
    {k, s} = api_key_fixture(t)
    ch = channel_fixture(t)

    fire = fn ->
      rnd = fn -> "x#{System.unique_integer([:positive])}" end

      body =
        Map.new(1..300, fn _ -> {rnd.(), 1} end)
        |> Map.merge(%{
          "channel_id" => ch.id,
          "recipient" => "+6281234567890",
          "text" => "Halo",
          "metadata" => Map.new(1..10, fn _ -> {rnd.(), rnd.()} end),
          "category" => rnd.()
        })

      build_conn()
      |> put_api_auth(k.client_key, s)
      |> put_req_header("idempotency-key", rnd.())
      |> post_json("/api/v1/messages", body)

      signed_webhook_post(
        build_conn(),
        Jason.encode!(%{"message_id" => Ecto.UUID.generate(), "status" => rnd.(), rnd.() => 1})
      )
    end

    # warm-up: loads every module on the same code path
    fire.()
    before = :erlang.system_info(:atom_count)
    for _ <- 1..5, do: fire.()
    assert :erlang.system_info(:atom_count) - before <= 5
  end

  test "lib/ contains no atom-minting calls" do
    offenders =
      for f <- Path.wildcard("lib/**/*.ex"),
          line <- File.stream!(f),
          line =~
            ~r/String\.to_atom|String\.to_existing_atom|binary_to_atom|List\.to_atom|keys: :atoms/,
          do: {f, line}

    assert offenders == []
  end
end
