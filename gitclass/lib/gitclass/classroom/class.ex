defmodule Gitclass.Classroom.Class do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "classes" do
    field :name, :string
    field :term, :string

    belongs_to :teacher, Gitclass.Accounts.User, type: :binary_id
    has_many :students, Gitclass.Classroom.ClassStudent
    has_many :commit_activities, Gitclass.Classroom.CommitActivity

    timestamps()
  end

  @doc false
  def changeset(class, attrs) do
    class
    |> cast(attrs, [:name, :term, :teacher_id])
    |> validate_required([:name, :teacher_id])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:term, max: 100)
    |> foreign_key_constraint(:teacher_id)
  end
end