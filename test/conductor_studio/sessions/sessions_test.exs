defmodule ConductorStudio.SessionsTest do
  use ConductorStudio.DataCase, async: false

  alias ConductorStudio.Projects
  alias ConductorStudio.Sessions
  alias ConductorStudio.Sessions.SessionRegistry

  describe "reconcile_task_running_state/1" do
    test "marks stale running task and sessions as failed" do
      {:ok, project} =
        Projects.create_project(%{
          name: "Reconcile Project",
          path: System.tmp_dir!()
        })

      {:ok, task} =
        Projects.create_task(%{
          title: "Reconcile Task",
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

      assert {:ok, updated_task} = Sessions.reconcile_task_running_state(task.id)
      assert updated_task.status == "failed"

      updated_session = Sessions.get_session!(session.id)
      assert updated_session.status == "failed"
      assert updated_session.exit_code == -1
      assert updated_session.finished_at != nil
    end

    test "keeps running task when a session process is active" do
      {:ok, project} =
        Projects.create_project(%{
          name: "Active Project",
          path: System.tmp_dir!()
        })

      {:ok, task} =
        Projects.create_task(%{
          title: "Active Task",
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

      {:ok, _} = Registry.register(SessionRegistry.name(), session.id, nil)

      assert {:ok, updated_task} = Sessions.reconcile_task_running_state(task.id)
      assert updated_task.status == "running"

      updated_session = Sessions.get_session!(session.id)
      assert updated_session.status == "running"
    end
  end

  describe "stop_running_session/1" do
    test "reconciles stale running state when process is not running" do
      {:ok, project} =
        Projects.create_project(%{
          name: "Stop Project",
          path: System.tmp_dir!()
        })

      {:ok, task} =
        Projects.create_task(%{
          title: "Stop Task",
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

      assert Sessions.stop_running_session(session.id) == :reconciled

      assert Projects.get_task!(task.id).status == "failed"
      assert Sessions.get_session!(session.id).status == "failed"
    end
  end
end
