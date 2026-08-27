defmodule Playstead.Repo do
  use Ecto.Repo,
    otp_app: :playstead,
    adapter: Ecto.Adapters.Postgres
end
