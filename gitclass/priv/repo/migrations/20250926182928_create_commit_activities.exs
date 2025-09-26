defmodule Gitclass.Repo.Migrations.CreateCommitActivities do
  use Ecto.Migration

  def change do
    create table(:commit_activities, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :class_id, references(:classes, type: :binary_id, on_delete: :delete_all), null: false
      add :student_username, :string, null: false
      add :commit_date, :date, null: false
      add :commit_count, :integer, default: 0
      add :last_commit_at, :utc_datetime
      add :repository_name, :string

      timestamps()
    end

    create index(:commit_activities, [:class_id, :student_username])
    create index(:commit_activities, [:commit_date])
    create unique_index(:commit_activities, [:class_id, :student_username, :commit_date, :repository_name])
  end
end
