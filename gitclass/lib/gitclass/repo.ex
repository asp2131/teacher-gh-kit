defmodule Gitclass.Repo do
  use Ecto.Repo,
    otp_app: :gitclass,
    adapter: Ecto.Adapters.Postgres
end
