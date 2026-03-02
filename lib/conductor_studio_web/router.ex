defmodule ConductorStudioWeb.Router do
  use ConductorStudioWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ConductorStudioWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ConductorStudioWeb do
    pipe_through :browser

    live "/", ProjectLive.Index, :index
    live "/projects/:id", ProjectLive.Show, :show
  end
end
