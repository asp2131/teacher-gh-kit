defmodule Gitclass.Accounts do
  @moduledoc """
  The Accounts context for managing users and authentication.
  """

  import Ecto.Query, warn: false
  alias Gitclass.Repo
  alias Gitclass.Accounts.User

  @doc """
  Gets a single user by ID.
  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Gets a user by GitHub ID.
  """
  def get_user_by_github_id(github_id) do
    Repo.get_by(User, github_id: github_id)
  end

  @doc """
  Gets a user by GitHub username.
  """
  def get_user_by_github_username(username) do
    Repo.get_by(User, github_username: username)
  end

  @doc """
  Creates or updates a user from GitHub OAuth data.
  """
  def create_or_update_user_from_github(github_user) do
    case get_user_by_github_id(github_user.id) do
      nil ->
        create_user_from_github(github_user)
      user ->
        update_user_from_github(user, github_user)
    end
  end

  defp create_user_from_github(github_user) do
    %User{}
    |> User.changeset(%{
      github_id: github_user.id,
      github_username: github_user.login,
      name: github_user.name,
      avatar_url: github_user.avatar_url,
      email: github_user.email
    })
    |> Repo.insert()
  end

  defp update_user_from_github(user, github_user) do
    user
    |> User.changeset(%{
      github_username: github_user.login,
      name: github_user.name,
      avatar_url: github_user.avatar_url,
      email: github_user.email
    })
    |> Repo.update()
  end

  @doc """
  Creates a user.
  """
  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a user.
  """
  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a user.
  """
  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.
  """
  def change_user(%User{} = user, attrs \\ %{}) do
    User.changeset(user, attrs)
  end
end