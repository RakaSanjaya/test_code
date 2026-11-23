# Demo data for local development:
#
#     mix ecto.reset        (or: mix run priv/repo/seeds.exs on an empty database)
#
# Prints the generated API credentials ONCE and writes them to
# tmp/seed_credentials.env (gitignored) so the README curl examples can
# `source` them. Secrets are random on every run and only their hashes are stored.

if Mix.env() == :prod, do: raise("seeds are for development only")

alias MessagingGateway.Accounts
alias MessagingGateway.Messaging.{Channel, Template}
alias MessagingGateway.Repo

insert! = fn struct, changeset_fun, attrs -> struct |> changeset_fun.(attrs) |> Repo.insert!() end

tenants = [
  %{
    name: "Acme Corp",
    balance: 100_000,
    status: "active",
    keys: [{"ACME", ["messages:write", "messages:read"]}, {"ACME_RO", ["messages:read"]}],
    channels: [
      {"ACME_WA", "whatsapp", "utility", true},
      {"ACME_SMS", "sms", "authentication", true},
      {"ACME_WA_OLD", "whatsapp", "marketing", false}
    ],
    templates: [
      {"otp_login_v1", "authentication", "approved", "Kode OTP Anda adalah {{1}}"},
      {"order_shipped_v1", "utility", "approved", "Halo {{1}}, pesanan {{2}} sedang dikirim."},
      {"promo_nov_v1", "marketing", "pending", "Diskon {{1}} khusus hari ini!"}
    ]
  },
  %{
    name: "Globex Inc",
    balance: 1_000,
    status: "active",
    keys: [{"GLOBEX", ["messages:write", "messages:read"]}, {"GLOBEX_WO", ["messages:write"]}],
    channels: [{"GLOBEX_WA", "whatsapp", "marketing", true}],
    templates: [
      {"otp_login_v1", "authentication", "approved", "Kode verifikasi Globex: {{1}}"}
    ]
  },
  %{
    name: "Initech",
    balance: 50_000,
    status: "suspended",
    keys: [{"INITECH", ["messages:write", "messages:read"]}],
    channels: [{"INITECH_SMS", "sms", "utility", true}],
    templates: []
  }
]

env_lines =
  Enum.flat_map(tenants, fn spec ->
    {:ok, tenant} =
      Accounts.create_tenant(Map.take(spec, [:name, :balance, :status]))

    key_lines =
      Enum.flat_map(spec.keys, fn {label, scopes} ->
        {:ok, key, secret} =
          Accounts.create_api_key(tenant, %{name: label, scopes: scopes})

        IO.puts(
          String.pad_trailing(label, 12) <>
            String.pad_trailing(tenant.name, 12) <>
            String.pad_trailing(Enum.join(scopes, ","), 30) <> key.client_key
        )

        ["#{label}_CLIENT_KEY=#{key.client_key}", "#{label}_SECRET=#{secret}"]
      end)

    channel_lines =
      Enum.map(spec.channels, fn {label, type, category, active} ->
        channel =
          insert!.(%Channel{}, &Channel.changeset/2, %{
            tenant_id: tenant.id,
            name: label,
            type: type,
            default_category: category,
            active: active
          })

        "#{label}_ID=#{channel.id}"
      end)

    for {code, category, status, body} <- spec.templates do
      insert!.(%Template{}, &Template.changeset/2, %{
        tenant_id: tenant.id,
        code: code,
        category: category,
        status: status,
        body_pattern: body
      })
    end

    key_lines ++ channel_lines
  end)

webhook_secret = Application.fetch_env!(:messaging_gateway, :webhook_secret)
port = System.get_env("PORT", "4000")

File.mkdir_p!("tmp")

File.write!(
  "tmp/seed_credentials.env",
  Enum.map_join(
    ["BASE_URL=http://localhost:#{port}" | env_lines] ++ ["WEBHOOK_SECRET=#{webhook_secret}"],
    "",
    &"export #{&1}\n"
  )
)

IO.puts(
  "\nCredentials (incl. secrets) written to tmp/seed_credentials.env — `source` it for curl."
)
