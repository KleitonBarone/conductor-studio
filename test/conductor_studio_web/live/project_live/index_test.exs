defmodule ConductorStudioWeb.ProjectLive.IndexTest do
  use ConductorStudioWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ConductorStudio.Projects

  describe "project deletion confirmation" do
    test "uses inline confirmation instead of browser alert", %{conn: conn} do
      {:ok, project} =
        Projects.create_project(%{
          name: "Delete Me",
          path: System.tmp_dir!()
        })

      {:ok, view, _html} = live(conn, ~p"/")

      render_click(view, "delete", %{"id" => "#{project.id}"})

      assert Projects.list_projects() != []

      render_click(view, "request_delete_project", %{"id" => "#{project.id}"})

      assert has_element?(view, "#project-delete-modal")

      render_click(view, "delete", %{"id" => "#{project.id}"})

      assert Projects.list_projects() == []
    end
  end
end
