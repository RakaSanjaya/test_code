defmodule MessagingGateway.Messaging.TemplateMatcherTest do
  use ExUnit.Case, async: true

  alias MessagingGateway.Messaging.{Template, TemplateMatcher}

  @otp "Kode OTP Anda adalah {{1}}"
  @ship "Halo {{1}}, pesanan {{2}} sedang dikirim."

  test "OTP template" do
    assert TemplateMatcher.matches?(@otp, "Kode OTP Anda adalah 849201")
    refute TemplateMatcher.matches?(@otp, "Kode OTP Anda adalah ")
    refute TemplateMatcher.matches?(@otp, "PROMO 90%! Kode OTP Anda adalah 1")
  end

  test "multi placeholder template rejects appended marketing text" do
    assert TemplateMatcher.matches?(@ship, "Halo Budi, pesanan #123 sedang dikirim.")

    refute TemplateMatcher.matches?(
             @ship,
             "Halo Budi, pesanan #123 sedang dikirim. Beli lagi diskon 50%!"
           )
  end

  test "no placeholders means exact match" do
    assert TemplateMatcher.matches?("Tanpa placeholder", "Tanpa placeholder")
    refute TemplateMatcher.matches?("Tanpa placeholder", "Tanpa placeholder!")
  end

  test "adjacent and repeated literals" do
    assert TemplateMatcher.matches?("{{1}}{{2}}", "ab")
    refute TemplateMatcher.matches?("{{1}}{{2}}", "a")
    assert TemplateMatcher.matches?("A {{1}} B {{2}} B", "A x B y B")
    refute TemplateMatcher.matches?("A {{1}} B {{2}} B", "A x B B")
  end

  test "regex metacharacters in the pattern are literal" do
    assert TemplateMatcher.matches?("Harga (promo) {{1}}.*", "Harga (promo) 10.*")
    refute TemplateMatcher.matches?("Harga (promo) {{1}}.*", "Harga (promo) 10xx")
  end

  test "pathological input finishes fast" do
    pattern = Enum.map_join(1..10, " ", &"{{#{&1}}}") <> "!"

    {us, false} =
      :timer.tc(fn -> TemplateMatcher.matches?(pattern, String.duplicate("a ", 2048)) end)

    assert us < 50_000
  end

  test "valid_pattern?/1" do
    assert TemplateMatcher.valid_pattern?(@otp)
    refute TemplateMatcher.valid_pattern?(Enum.map_join(1..11, " ", &"{{#{&1}}}"))
    refute TemplateMatcher.valid_pattern?(String.duplicate("a", 1025))
  end

  test "Template.changeset/2 rejects invalid body patterns" do
    cs =
      Template.changeset(%Template{}, %{
        tenant_id: Ecto.UUID.generate(),
        code: "too_many",
        category: "utility",
        status: "approved",
        body_pattern: Enum.map_join(1..11, " ", &"{{#{&1}}}")
      })

    assert {_, _} = cs.errors[:body_pattern]
  end
end
