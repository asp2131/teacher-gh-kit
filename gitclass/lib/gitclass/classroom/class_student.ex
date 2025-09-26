defmodule Gitclass.Classroom.ClassStudent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "class_students" do
    field :student_github_username, :string
    field :student_name, :string
    field :student_avatar_url, :string
    field :has_pages_repo, :boolean, default: false
    field :pages_repo_url, :string
    field :live_site_url, :string
    field :last_commit_at, :utc_datetime
    field :verification_status, :string, default: "pending"
    field :added_at, :utc_datetime

    belongs_to :class, Gitclass.Classroom.Class, type: :binary_id

    timestamps()
  end

  @doc false
  def changeset(class_student, attrs) do
    class_student
    |> cast(attrs, [
      :student_github_username, :student_name, :student_avatar_url,
      :has_pages_repo, :pages_repo_url, :live_site_url,
      :last_commit_at, :verification_status, :added_at, :class_id
    ])
    |> validate_required([:student_github_username, :class_id])
    |> validate_format(:student_github_username, ~r/^[a-zA-Z0-9]([a-zA-Z0-9]|-(?=[a-zA-Z0-9])){0,38}$/, 
        message: "must be a valid GitHub username")
    |> validate_inclusion(:verification_status, ["pending", "verified", "missing", "invalid"])
    |> foreign_key_constraint(:class_id)
    |> unique_constraint([:class_id, :student_github_username])
  end
end