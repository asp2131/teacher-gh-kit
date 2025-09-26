defmodule Gitclass.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Gitclass.Accounts` context.
  """

  @doc """
  Generate a user.
  """
  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> Enum.into(%{
        github_id: System.unique_integer([:positive]),
        github_username: "user#{System.unique_integer([:positive])}",
        name: "Test User",
        email: "test#{System.unique_integer([:positive])}@example.com"
      })
      |> Gitclass.Accounts.create_user()

    user
  end
end