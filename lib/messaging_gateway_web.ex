defmodule MessagingGatewayWeb do
  @moduledoc """
  The entrypoint for defining the JSON API web interface (router and controllers).

  This can be used in your application as:

      use MessagingGatewayWeb, :controller
      use MessagingGatewayWeb, :router

  The definitions below will be executed for every controller,
  component, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define additional modules and import
  those modules here.
  """

  def router do
    quote do
      use Phoenix.Router, helpers: false

      # Import common connection and controller functions to use in pipelines
      import Plug.Conn
      import Phoenix.Controller
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:json]

      import Plug.Conn
    end
  end

  @doc """
  When used, dispatch to the appropriate router/controller definition.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
