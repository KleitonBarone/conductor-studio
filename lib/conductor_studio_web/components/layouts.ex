defmodule ConductorStudioWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use ConductorStudioWeb, :html

  embed_templates "layouts/*"

  @doc """
  Renders your app layout.
  """
  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col">
      <header class="navbar bg-base-200 px-4 sticky top-0 z-50 shadow-sm">
        <div class="flex-1">
          <a href="/" class="flex items-center gap-2 font-semibold text-lg">
            <.icon name="hero-command-line" class="size-6 text-primary" />
            <span>Conductor Studio</span>
          </a>
        </div>
        <div class="flex-none">
          <.theme_toggle />
        </div>
      </header>

      <main class="flex-1">
        {render_slot(@inner_block)}
      </main>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="flex items-center gap-1 bg-base-300 rounded-full p-1">
      <button
        class="btn btn-ghost btn-circle btn-sm"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        title="Light mode"
      >
        <.icon name="hero-sun-micro" class="size-4" />
      </button>
      <button
        class="btn btn-ghost btn-circle btn-sm"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        title="Dark mode"
      >
        <.icon name="hero-moon-micro" class="size-4" />
      </button>
    </div>
    """
  end
end
