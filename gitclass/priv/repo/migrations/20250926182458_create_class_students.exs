defmodule Gitclass.Repo.Migrations.CreateClassStudents do
  use Ecto.Migration

  def change do
    create table(:class_students, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :class_id, references(:classes, type: :binary_id, on_delete: :delete_all), null: false
      add :student_github_username, :string, null: false
      add :student_name, :string
      add :student_avatar_url, :text
      add :has_pages_repo, :boolean, default: false
      add :pages_repo_url, :text
      add :live_site_url, :text
      add :last_commit_at, :utc_datetime
      add :verification_status, :string, default: "pending"
      add :added_at, :utc_datetime

      timestamps()
    end

    create index(:class_students, [:class_id])
    create unique_index(:class_students, [:class_id, :student_github_username])
  end
end
