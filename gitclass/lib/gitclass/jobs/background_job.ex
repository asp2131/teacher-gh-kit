defmodule Gitclass.Jobs.BackgroundJob do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "background_jobs" do
    field :job_type, :string
    field :status, :string, default: "queued"
    field :progress, :integer, default: 0
    field :total, :integer, default: 0
    field :error_message, :string
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to :class, Gitclass.Classroom.Class, type: :binary_id

    timestamps()
  end

  @doc false
  def changeset(background_job, attrs) do
    background_job
    |> cast(attrs, [
      :job_type, :status, :progress, :total, :error_message,
      :started_at, :completed_at, :class_id
    ])
    |> validate_required([:job_type])
    |> validate_inclusion(:status, ["queued", "running", "completed", "failed"])
    |> validate_number(:progress, greater_than_or_equal_to: 0)
    |> validate_number(:total, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:class_id)
  end
end