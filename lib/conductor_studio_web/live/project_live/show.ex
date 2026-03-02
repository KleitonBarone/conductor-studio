defmodule ConductorStudioWeb.ProjectLive.Show do
  @moduledoc """
  LiveView for the project board - Kanban-style task management.
  """
  use ConductorStudioWeb, :live_view

  alias ConductorStudio.Projects
  alias ConductorStudio.Projects.Task
  alias ConductorStudio.Sessions

  import ConductorStudioWeb.BoardComponents

  @statuses ["pending", "running", "completed", "failed"]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    project = Projects.get_project_with_tasks!(id)

    if connected?(socket) do
      subscribe_to_running_sessions(project.tasks)
    end

    socket =
      socket
      |> assign(:project, project)
      |> assign(:tasks_by_status, group_tasks_by_status(project.tasks))
      |> assign(:selected_task, nil)
      |> assign(:selected_session, nil)
      |> assign(:streaming_content, [])
      |> assign(:messages, [])
      |> assign(:task_form_error, nil)
      |> assign(:task_action_error, nil)
      |> assign(:confirm_delete_task_id, nil)
      |> assign(:task_card_errors, %{})
      |> assign(:show_task_form, false)
      |> assign(:task_form, to_form(Projects.change_task(%Task{})))

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, :page_title, socket.assigns.project.name)}
  end

  # ─────────────────────────────────────────────────────────────
  # Event Handlers
  # ─────────────────────────────────────────────────────────────

  @impl true
  def handle_event("open_task_form", _params, socket) do
    socket =
      socket
      |> assign(:show_task_form, true)
      |> assign(:task_form_error, nil)
      |> assign(:task_form, to_form(Projects.change_task(%Task{})))

    {:noreply, socket}
  end

  def handle_event("close_task_form", _params, socket) do
    socket =
      socket
      |> assign(:show_task_form, false)
      |> assign(:task_form_error, nil)
      |> assign(:task_form, to_form(Projects.change_task(%Task{})))

    {:noreply, socket}
  end

  def handle_event("validate_task", %{"task" => params}, socket) do
    changeset =
      %Task{}
      |> Projects.change_task(params)
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign(:task_form_error, nil) |> assign(:task_form, to_form(changeset))}
  end

  def handle_event("save_task", %{"task" => params}, socket) do
    params = Map.put(params, "project_id", socket.assigns.project.id)

    case Projects.create_task(params) do
      {:ok, _task} ->
        socket =
          socket
          |> assign(:show_task_form, false)
          |> assign(:task_form_error, nil)
          |> assign(:task_form, to_form(Projects.change_task(%Task{})))
          |> refresh_tasks()
          |> assign(:task_action_error, nil)

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:task_form_error, "Could not create task. Check the fields and try again.")
         |> assign(:task_form, to_form(changeset))}
    end
  end

  def handle_event("select_task", %{"id" => id}, socket) do
    task = Projects.get_task!(id)
    session = Sessions.get_latest_session(task.id)
    messages = if session, do: Sessions.list_messages(session.id), else: []

    if session && session.status == "running" do
      Phoenix.PubSub.subscribe(ConductorStudio.PubSub, "session:#{session.id}")
    end

    socket =
      socket
      |> assign(:selected_task, task)
      |> assign(:selected_session, session)
      |> assign(:messages, messages)
      |> assign(:confirm_delete_task_id, nil)
      |> assign(:task_action_error, nil)
      |> update(:task_card_errors, &Map.delete(&1, task.id))
      |> assign(:streaming_content, [])

    {:noreply, socket}
  end

  def handle_event("close_detail", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_task, nil)
     |> assign(:selected_session, nil)
     |> assign(:confirm_delete_task_id, nil)
     |> assign(:task_action_error, nil)
     |> assign(:messages, [])
     |> assign(:streaming_content, [])}
  end

  def handle_event("request_delete_task", %{"id" => id}, socket) do
    task = Projects.get_task!(id)

    if task.status == "running" do
      {:noreply, assign(socket, :task_action_error, "Cannot delete a running task")}
    else
      {:noreply,
       socket
       |> assign(:task_action_error, nil)
       |> assign(:confirm_delete_task_id, task.id)}
    end
  end

  def handle_event("cancel_delete_task", _params, socket) do
    {:noreply, assign(socket, :confirm_delete_task_id, nil)}
  end

  def handle_event("run_task", %{"id" => id}, socket) do
    task = Projects.get_task!(id)

    case Sessions.create_and_run_session(%{task_id: task.id}) do
      {:ok, session, _pid} ->
        Phoenix.PubSub.subscribe(ConductorStudio.PubSub, "session:#{session.id}")
        {:ok, updated_task} = Projects.update_task_status(task, "running")

        socket =
          socket
          |> refresh_tasks()
          |> assign(:selected_task, updated_task)
          |> assign(:selected_session, session)
          |> assign(:confirm_delete_task_id, nil)
          |> assign(:task_action_error, nil)
          |> update(:task_card_errors, &Map.delete(&1, task.id))
          |> assign(:messages, [])
          |> assign(:streaming_content, [])

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign_run_error(socket, task.id, "Failed to start: #{inspect(reason)}")}
    end
  end

  def handle_event("stop_session", %{"id" => id}, socket) do
    session_id = String.to_integer(id)

    case Sessions.stop_running_session(session_id) do
      :ok ->
        {:noreply, assign(socket, :task_action_error, nil)}

      :reconciled ->
        {selected_task, selected_session, messages} =
          if socket.assigns.selected_task do
            task = Projects.get_task!(socket.assigns.selected_task.id)
            session = Sessions.get_latest_session(task.id)
            msgs = if session, do: Sessions.list_messages(session.id), else: []
            {task, session, msgs}
          else
            {nil, nil, []}
          end

        {:noreply,
         socket
         |> refresh_tasks()
         |> assign(:selected_task, selected_task)
         |> assign(:selected_session, selected_session)
         |> assign(:messages, messages)
         |> assign(:task_action_error, nil)
         |> assign(:streaming_content, [])}

      {:error, reason} ->
        {:noreply, assign(socket, :task_action_error, "Failed to stop: #{inspect(reason)}")}
    end
  end

  def handle_event("delete_task", %{"id" => id}, socket) do
    task = Projects.get_task!(id)

    # Don't allow deleting running tasks
    if task.status == "running" do
      {:noreply, assign(socket, :task_action_error, "Cannot delete a running task")}
    else
      {:ok, _} = Projects.delete_task(task)

      socket =
        socket
        |> assign(:selected_task, nil)
        |> assign(:selected_session, nil)
        |> assign(:confirm_delete_task_id, nil)
        |> assign(:task_action_error, nil)
        |> update(:task_card_errors, &Map.delete(&1, task.id))
        |> assign(:messages, [])
        |> assign(:streaming_content, [])
        |> refresh_tasks()

      {:noreply, socket}
    end
  end

  # ─────────────────────────────────────────────────────────────
  # PubSub Handlers
  # ─────────────────────────────────────────────────────────────

  @impl true
  def handle_info({:session_started, _}, socket), do: {:noreply, refresh_tasks(socket)}

  def handle_info({:session_completed, %{exit_code: _exit_code}}, socket) do
    # Reload task and session from database to get updated status
    {selected_task, selected_session, messages} =
      if socket.assigns.selected_task do
        task = Projects.get_task!(socket.assigns.selected_task.id)
        session = Sessions.get_latest_session(task.id)
        msgs = if session, do: Sessions.list_messages(session.id), else: []
        {task, session, msgs}
      else
        {nil, nil, []}
      end

    {:noreply,
     socket
     |> refresh_tasks()
     |> assign(:selected_task, selected_task)
     |> assign(:selected_session, selected_session)
     |> assign(:confirm_delete_task_id, nil)
     |> assign(:messages, messages)
     |> assign(:streaming_content, [])}
  end

  def handle_info({:session_failed, %{reason: reason}}, socket) do
    selected_task_id = socket.assigns.selected_task && socket.assigns.selected_task.id

    if selected_task_id do
      _ = Sessions.reconcile_task_running_state(selected_task_id)
      Process.send_after(self(), {:refresh_task_state, selected_task_id}, 100)
    end

    # Reload task and session from database to get updated status
    {selected_task, selected_session} =
      if socket.assigns.selected_task do
        task = Projects.get_task!(socket.assigns.selected_task.id)
        session = Sessions.get_latest_session(task.id)
        {task, session}
      else
        {nil, nil}
      end

    {:noreply,
     socket
     |> refresh_tasks()
     |> assign(:selected_task, selected_task)
     |> assign(:selected_session, selected_session)
     |> assign(:confirm_delete_task_id, nil)
     |> assign(:task_action_error, nil)
     |> assign(:streaming_content, [])
     |> assign(:task_action_error, "Session failed: #{inspect(reason)}")}
  end

  def handle_info({:refresh_task_state, task_id}, socket) do
    selected_task = socket.assigns.selected_task

    if selected_task && selected_task.id == task_id do
      task = Projects.get_task!(task_id)
      session = Sessions.get_latest_session(task.id)
      messages = if session, do: Sessions.list_messages(session.id), else: []

      {:noreply,
       socket
       |> refresh_tasks()
       |> assign(:selected_task, task)
       |> assign(:selected_session, session)
       |> assign(:confirm_delete_task_id, nil)
       |> assign(:messages, messages)
       |> assign(:streaming_content, [])}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:message, %{role: role, content: content}}, socket) do
    new_content = {System.unique_integer(), "#{role}: #{content}"}

    {:noreply, update(socket, :streaming_content, &(&1 ++ [new_content]))}
  end

  def handle_info({:content_delta, %{"delta" => %{"text" => text}}}, socket) do
    {:noreply,
     update(socket, :streaming_content, fn list ->
       case list do
         [] ->
           [{System.unique_integer(), text}]

         _ ->
           {id, last} = List.last(list)
           List.replace_at(list, -1, {id, last <> text})
       end
     end)}
  end

  def handle_info({:tool_use, %{"name" => name}}, socket) do
    new_content = {System.unique_integer(), "[Tool: #{name}]"}
    {:noreply, update(socket, :streaming_content, &(&1 ++ [new_content]))}
  end

  def handle_info({event, _}, socket)
      when event in [
             :tool_result,
             :content_block_start,
             :content_block_stop,
             :message_start,
             :message_stop,
             :session_terminated,
             :unknown_event
           ] do
    {:noreply, socket}
  end

  # ─────────────────────────────────────────────────────────────
  # Private
  # ─────────────────────────────────────────────────────────────

  defp subscribe_to_running_sessions(tasks) do
    tasks
    |> Enum.filter(&(&1.status == "running"))
    |> Enum.each(fn task ->
      if session = Sessions.get_running_session(task.id) do
        Phoenix.PubSub.subscribe(ConductorStudio.PubSub, "session:#{session.id}")
      end
    end)
  end

  defp group_tasks_by_status(tasks) do
    grouped = Enum.group_by(tasks, & &1.status)
    Map.new(@statuses, fn s -> {s, Map.get(grouped, s, [])} end)
  end

  defp refresh_tasks(socket) do
    project = Projects.get_project_with_tasks!(socket.assigns.project.id)

    socket
    |> assign(:project, project)
    |> assign(:tasks_by_status, group_tasks_by_status(project.tasks))
  end

  defp status_title("pending"), do: "Pending"
  defp status_title("running"), do: "Running"
  defp status_title("completed"), do: "Completed"
  defp status_title("failed"), do: "Failed"
  defp status_title(s), do: String.capitalize(s)

  defp message_class("assistant"), do: "text-success"
  defp message_class("user"), do: "text-info"
  defp message_class("tool"), do: "text-warning"
  defp message_class(_), do: "text-base-content"

  defp assign_run_error(socket, task_id, message) do
    socket
    |> update(:task_card_errors, &Map.put(&1, task_id, message))
    |> then(fn sock ->
      selected_task = sock.assigns.selected_task

      if selected_task && selected_task.id == task_id do
        assign(sock, :task_action_error, message)
      else
        sock
      end
    end)
  end

  # ─────────────────────────────────────────────────────────────
  # Render
  # ─────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :statuses, @statuses)

    ~H"""
    <Layouts.app>
      <div class="flex flex-col h-[calc(100vh-4rem)]">
        <%!-- Header --%>
        <div class="p-4 border-b border-base-300 flex flex-col sm:flex-row sm:items-center justify-between gap-2">
          <div class="flex items-center gap-2 min-w-0">
            <.link navigate={~p"/"} class="btn btn-ghost btn-sm btn-circle shrink-0">
              <.icon name="hero-arrow-left" class="size-5" />
            </.link>
            <div class="min-w-0">
              <h1 class="font-bold truncate">{@project.name}</h1>
              <p class="text-xs text-base-content/60 font-mono truncate">{@project.path}</p>
            </div>
          </div>
          <button
            phx-click="open_task_form"
            class="btn btn-primary btn-sm shrink-0"
          >
            <.icon name="hero-plus" class="size-4" /> Add Task
          </button>
        </div>

        <%!-- Add task modal --%>
        <.modal
          :if={@show_task_form}
          id="task-form-modal"
          show
          on_cancel={JS.push("close_task_form")}
        >
          <h3 class="font-semibold text-lg mb-4">Add Task</h3>

          <div :if={@task_form_error} class="alert alert-error mb-4 py-2 text-sm">
            {@task_form_error}
          </div>

          <.form for={@task_form} phx-change="validate_task" phx-submit="save_task" class="space-y-3">
            <.input
              field={@task_form[:title]}
              type="text"
              label="Task title"
              placeholder="Task title"
              phx-debounce="200"
            />
            <.input
              field={@task_form[:prompt]}
              type="textarea"
              label="Prompt"
              placeholder="Prompt for the LLM..."
              rows="5"
              phx-debounce="200"
            />

            <div class="flex justify-end gap-2 pt-2">
              <button type="button" class="btn btn-ghost btn-sm" phx-click="close_task_form">
                Cancel
              </button>
              <.button class="btn btn-primary btn-sm">
                <.icon name="hero-plus" class="size-4" /> Add
              </.button>
            </div>
          </.form>
        </.modal>

        <%!-- Main content area --%>
        <div class="flex-1 flex overflow-hidden">
          <%!-- Kanban Board --%>
          <div class={[
            "flex-1 overflow-x-auto p-4",
            @selected_task && "hidden lg:block lg:w-1/2 xl:w-2/3"
          ]}>
            <div class="flex gap-4 min-w-max h-full">
              <div :for={status <- @statuses} class="w-64 flex flex-col">
                <div class="flex items-center gap-2 mb-2 px-1">
                  <h3 class="font-medium text-sm">{status_title(status)}</h3>
                  <span class="badge badge-xs badge-ghost">
                    {length(Map.get(@tasks_by_status, status, []))}
                  </span>
                </div>
                <div class="flex-1 bg-base-200/50 rounded-lg p-2 space-y-2 overflow-y-auto">
                  <div
                    :for={task <- Map.get(@tasks_by_status, status, [])}
                    class={[
                      "card bg-base-100 shadow-sm cursor-pointer hover:shadow transition-all",
                      @selected_task && @selected_task.id == task.id && "ring-2 ring-primary"
                    ]}
                    phx-click="select_task"
                    phx-value-id={task.id}
                  >
                    <div class="card-body p-3">
                      <h4 class="font-medium text-sm leading-tight">{task.title}</h4>
                      <p :if={task.prompt} class="text-xs text-base-content/60 line-clamp-2">
                        {task.prompt}
                      </p>
                      <div class="flex items-center justify-between mt-1">
                        <.status_badge status={task.status} />
                        <button
                          :if={task.status in ["pending", "completed", "failed", "cancelled"]}
                          class="btn btn-primary btn-xs"
                          phx-click="run_task"
                          phx-value-id={task.id}
                        >
                          <.icon name="hero-play" class="size-3" />
                        </button>
                        <span
                          :if={task.status == "running"}
                          class="loading loading-spinner loading-xs text-info"
                        />
                      </div>
                      <div :if={Map.get(@task_card_errors, task.id)} class="text-error text-xs mt-2">
                        {Map.get(@task_card_errors, task.id)}
                      </div>
                    </div>
                  </div>
                  <div
                    :if={Map.get(@tasks_by_status, status, []) == []}
                    class="text-center text-base-content/40 py-8 text-xs"
                  >
                    No tasks
                  </div>
                </div>
              </div>
            </div>
          </div>

          <%!-- Task Detail Panel --%>
          <div
            :if={@selected_task}
            class="w-full lg:w-1/2 xl:w-1/3 border-l border-base-300 flex flex-col bg-base-100"
          >
            <div class="flex items-center justify-between p-3 border-b border-base-300">
              <h2 class="font-semibold truncate">{@selected_task.title}</h2>
              <button class="btn btn-ghost btn-sm btn-circle" phx-click="close_detail">
                <.icon name="hero-x-mark" class="size-5" />
              </button>
            </div>

            <div class="flex-1 overflow-y-auto p-3 space-y-3">
              <%!-- Prompt --%>
              <div>
                <h4 class="text-xs font-medium text-base-content/60 mb-1">Prompt</h4>
                <pre class="text-sm bg-base-200 rounded p-2 whitespace-pre-wrap">{@selected_task.prompt || "(empty)"}</pre>
              </div>

              <%!-- Actions --%>
              <div class="flex gap-2">
                <button
                  :if={@selected_task.status in ["pending", "completed", "failed", "cancelled"]}
                  class="btn btn-primary btn-sm flex-1"
                  phx-click="run_task"
                  phx-value-id={@selected_task.id}
                >
                  <.icon name="hero-play" class="size-4" /> Run
                </button>
                <button
                  :if={@selected_task.status == "running" && @selected_session}
                  class="btn btn-error btn-sm flex-1"
                  phx-click="stop_session"
                  phx-value-id={@selected_session.id}
                >
                  <.icon name="hero-stop" class="size-4" /> Stop
                </button>
                <button
                  :if={@selected_task.status != "running"}
                  class="btn btn-ghost btn-sm text-error"
                  phx-click="request_delete_task"
                  phx-value-id={@selected_task.id}
                >
                  <.icon name="hero-trash" class="size-4" />
                </button>
              </div>

              <div
                :if={
                  @confirm_delete_task_id == @selected_task.id && @selected_task.status != "running"
                }
                class="alert alert-warning py-2 text-sm"
              >
                <div class="flex items-center justify-between w-full gap-3">
                  <span>Delete this task?</span>
                  <div class="flex items-center gap-2">
                    <button
                      type="button"
                      class="btn btn-ghost btn-xs"
                      phx-click="cancel_delete_task"
                    >
                      Cancel
                    </button>
                    <button
                      type="button"
                      class="btn btn-error btn-xs"
                      phx-click="delete_task"
                      phx-value-id={@selected_task.id}
                    >
                      Delete
                    </button>
                  </div>
                </div>
              </div>

              <div :if={@task_action_error} class="alert alert-error py-2 text-sm">
                {@task_action_error}
              </div>

              <%!-- Session Output --%>
              <div :if={@selected_session || @streaming_content != []}>
                <div class="flex items-center gap-2 mb-1">
                  <h4 class="text-xs font-medium text-base-content/60">Output</h4>
                  <span
                    :if={@selected_task.status == "running"}
                    class="loading loading-dots loading-xs"
                  />
                </div>
                <div
                  id="session-output"
                  class="bg-base-200 rounded p-2 h-64 overflow-y-auto font-mono text-xs space-y-1"
                  phx-hook="ScrollBottom"
                >
                  <div :for={msg <- @messages} class={message_class(msg.role)}>
                    <span class="opacity-60">{msg.role}:</span> {msg.content}
                  </div>
                  <div
                    :for={{id, content} <- @streaming_content}
                    id={"s-#{id}"}
                    class="text-primary whitespace-pre-wrap"
                  >
                    {content}
                  </div>
                  <div
                    :if={
                      @selected_task.status == "running" && @streaming_content == [] &&
                        @messages == []
                    }
                    class="text-base-content/40"
                  >
                    Waiting...
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
