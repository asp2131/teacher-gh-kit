defmodule Gitclass.Classroom.CommitActivity do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "commit_activities" do
    field :student_username, :string
    field :commit_date, :date
    field :commit_count, :integer, default: 0
    field :last_commit_at, :utc_datetime
    field :repository_name, :string

    belongs_to :class, Gitclass.Classroom.Class, type: :binary_id

    timestamps()
  end

  @doc false
  def changeset(commit_activity, attrs) do
    commit_activity
    |> cast(attrs, [:student_username, :commit_date, :commit_count, :last_commit_at, :repository_name, :class_id])
    |> validate_required([:student_username, :commit_date, :class_id])
    |> validate_number(:commit_count, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:class_id)
  end
end