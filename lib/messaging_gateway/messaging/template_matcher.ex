defmodule MessagingGateway.Messaging.TemplateMatcher do
  @moduledoc """
  Checks that a message text is an instance of a template `body_pattern`.

  Placeholders look like `{{1}}` and stand for one or more bytes; everything else
  in the pattern is literal. This stops a tenant from sending free-form marketing
  copy under a cheap `authentication` template.

  The match is a greedy-leftmost scan over the literal segments using
  `:binary.match/3`: linear time, and no regex is ever compiled from tenant data
  (so no ReDoS and no metacharacter surprises).
  """

  @placeholder ~r/\{\{\d{1,2}\}\}/
  @max_pattern_bytes 1024
  @max_placeholders 10

  @spec valid_pattern?(term()) :: boolean()
  def valid_pattern?(pattern) when is_binary(pattern) do
    byte_size(pattern) in 1..@max_pattern_bytes and
      length(Regex.scan(@placeholder, pattern)) <= @max_placeholders
  end

  def valid_pattern?(_), do: false

  @spec matches?(String.t(), String.t()) :: boolean()
  def matches?(pattern, text) when is_binary(pattern) and is_binary(text) do
    case String.split(pattern, @placeholder) do
      [literal] -> text == literal
      [first | rest] -> match_segments(text, first, rest)
    end
  end

  def matches?(_, _), do: false

  defp match_segments(text, first, rest) do
    {middle, [last]} = Enum.split(rest, -1)

    if String.starts_with?(text, first) do
      case consume_middle(text, byte_size(first), middle) do
        {:ok, pos} -> ends_with_after?(text, pos, last)
        :error -> false
      end
    else
      false
    end
  end

  # Each placeholder must consume at least one byte, so every literal is searched
  # for starting one byte after the current position.
  defp consume_middle(_text, pos, []), do: {:ok, pos}

  defp consume_middle(text, pos, [segment | rest]) do
    start = pos + 1
    size = byte_size(text)

    cond do
      start > size ->
        :error

      segment == "" ->
        consume_middle(text, start, rest)

      true ->
        case :binary.match(text, segment, scope: {start, size - start}) do
          {index, length} -> consume_middle(text, index + length, rest)
          :nomatch -> :error
        end
    end
  end

  defp ends_with_after?(text, pos, last) do
    size = byte_size(text)
    last_size = byte_size(last)

    size - pos >= last_size + 1 and binary_part(text, size - last_size, last_size) == last
  end
end
