defmodule Gitclass.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :github_id, :integer
    field :github_username, :string
    field :name, :string
    field :avatar_url, :string
    field :email, :string

    has_many :classes, Gitclass.Classroom.Class, foreign_key: :teacher_id

    timestamps()
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:github_id, :github_username, :name, :avatar_url, :email])
    |> validate_required([:github_id, :github_username])
    |> validate_format(:github_username, ~r/^[a-zA-Z0-9]([a-zA-Z0-9]|-(?=[a-zA-Z0-9])){0,38}$/, 
        message: "must be a valid GitHub username")
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
    |> unique_constraint(:github_id)
    |> unique_constraint(:github_username)
  end
end