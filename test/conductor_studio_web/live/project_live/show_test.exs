defmodule ConductorStudioWeb.ProjectLive.ShowTest do
  use ConductorStudioWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ConductorStudio.Projects
  alias ConductorStudio.Sessions

  describe "stale running recovery" do
    test "stop reconciles stale running task and shows rerun action", %{conn: conn} do
      {:ok, project} =
        Projects.create_project(%{
          name: "LiveView Project",
          path: System.tmp_dir!()
        })

      {:ok, task} =
        Projects.create_task(%{
          title: "Stale Running Task",
          prompt: "test",
          project_id: project.id,
          status: "running"
        })

      {:ok, session} =
        Sessions.create_session(%{
          task_id: task.id,
          status: "running",
          started_at: DateTime.utc_now()
        })

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")

      view
      |> element("[phx-click='select_task'][phx-value-id='#{task.id}']")
      |> render_click()

      assert has_element?(view, "[phx-click='stop_session'][phx-value-id='#{session.id}']")

      view
      |> element("[phx-click='stop_session'][phx-value-id='#{session.id}']")
      |> render_click()

      refute has_element?(view, "[phx-click='stop_session'][phx-value-id='#{session.id}']")
      assert has_element?(view, "[phx-click='run_task'][phx-value-id='#{task.id}']")

      assert Projects.get_task!(task.id).status == "failed"
      assert Sessions.get_session!(session.id).status == "failed"
    end

    test "session_failed event also refreshes stale running UI state", %{conn: conn} do
      {:ok, project} =
        Projects.create_project(%{
          name: "LiveView Failure Refresh",
          path: System.tmp_dir!()
        })

      {:ok, task} =
        Projects.create_task(%{
          title: "Failure Event Task",
          prompt: "test",
          project_id: project.id,
          status: "running"
        })

      {:ok, session} =
        Sessions.create_session(%{
          task_id: task.id,
          status: "running",
          started_at: DateTime.utc_now()
        })

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}")

      view
      |> element("[phx-click='select_task'][phx-value-id='#{task.id}']")
      |> render_click()

      assert has_element?(view, "[phx-click='stop_session'][phx-value-id='#{session.id}']")

      send(view.pid, {:session_failed, %{reason: :provider_crashed}})

      Process.sleep(150)

      refute has_element?(view, "[phx-click='stop_session'][phx-value-id='#{session.id}']")
      assert has_element?(view, "[phx-click='run_task'][phx-value-id='#{task.id}']")

      assert Projects.get_task!(task.id).status == "failed"
      assert Sessions.get_session!(session.id).status == "failed"
    end
  end
end
