defmodule ConductorStudioWeb.PageControllerTest do
  use ConductorStudioWeb.ConnCase

  test "GET / renders project list", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Projects"
  end
end
