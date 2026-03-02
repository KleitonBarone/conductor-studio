defmodule ConductorStudio.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ConductorStudioWeb.Telemetry,
      ConductorStudio.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:conductor_studio, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:conductor_studio, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ConductorStudio.PubSub},
      # Session management for LLM execution workers
      ConductorStudio.Sessions.SessionRegistry,
      ConductorStudio.Sessions.SessionSupervisor,
      # Start to serve requests, typically the last entry
      ConductorStudioWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ConductorStudio.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        # Clean up any orphaned sessions from previous runs
        reset_count = ConductorStudio.Sessions.reset_orphaned_sessions()

        if reset_count > 0 do
          require Logger
          Logger.info("Reset #{reset_count} orphaned session(s) on startup")
        end

        {:ok, pid}

      error ->
        error
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ConductorStudioWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations? do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
