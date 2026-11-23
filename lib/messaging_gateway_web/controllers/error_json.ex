defmodule MessagingGatewayWeb.ErrorJSON do
  @moduledoc """
  Renders framework-level errors (no route, parse errors, crashes) in the API's
  standard error envelope: `%{error: %{code: "...", message: "..."}}`.
  """

  def render(template, _assigns) do
    %{
      error: %{
        code: code_from_template(template),
        message: Phoenix.Controller.status_message_from_template(template)
      }
    }
  end

  defp code_from_template(template) do
    with [status_text | _] <- String.split(template, "."),
         {status, ""} <- Integer.parse(status_text) do
      status |> Plug.Conn.Status.reason_atom() |> Atom.to_string()
    else
      _ -> "internal_server_error"
    end
  rescue
    ArgumentError -> "internal_server_error"
  end
end
