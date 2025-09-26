defmodule Gitclass.Repo.Migrations.CreateBackgroundJobs do
  use Ecto.Migration

  def change do
    create table(:background_jobs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :class_id, references(:classes, type: :binary_id, on_delete: :delete_all)
      add :job_type, :string, null: false
      add :status, :string, default: "queued"
      add :progress, :integer, default: 0
      add :total, :integer, default: 0
      add :error_message, :text
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps()
    end

    create index(:background_jobs, [:status])
    create index(:background_jobs, [:class_id])
    create index(:background_jobs, [:job_type])
  end
end
