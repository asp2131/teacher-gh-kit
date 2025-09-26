defmodule Gitclass.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :github_id, :bigint, null: false
      add :github_username, :string, null: false
      add :name, :string
      add :avatar_url, :text
      add :email, :string

      timestamps()
    end

    create unique_index(:users, [:github_id])
    create unique_index(:users, [:github_username])
  end
end
