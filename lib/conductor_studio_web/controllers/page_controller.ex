defmodule ConductorStudioWeb.PageController do
  use ConductorStudioWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
