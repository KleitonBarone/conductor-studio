defmodule ConductorStudio.Repo do
  use Ecto.Repo,
    otp_app: :conductor_studio,
    adapter: Ecto.Adapters.SQLite3
end
