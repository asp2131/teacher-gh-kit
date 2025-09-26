defmodule Gitclass.AccountsTest do
  use Gitclass.DataCase

  alias Gitclass.Accounts

  describe "users" do
    alias Gitclass.Accounts.User

    import Gitclass.AccountsFixtures

    @invalid_attrs %{github_id: nil, github_username: nil}

    test "get_user!/1 returns the user with given id" do
      user = user_fixture()
      assert Accounts.get_user!(user.id) == user
    end

    test "create_user/1 with valid data creates a user" do
      valid_attrs = %{
        github_id: 12345,
        github_username: "testuser",
        name: "Test User",
        email: "test@example.com"
      }

      assert {:ok, %User{} = user} = Accounts.create_user(valid_attrs)
      assert user.github_id == 12345
      assert user.github_username == "testuser"
      assert user.name == "Test User"
      assert user.email == "test@example.com"
    end

    test "create_user/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Accounts.create_user(@invalid_attrs)
    end

    test "get_user_by_github_id/1 returns user when exists" do
      user = user_fixture()
      assert Accounts.get_user_by_github_id(user.github_id) == user
    end

    test "get_user_by_github_id/1 returns nil when user doesn't exist" do
      assert Accounts.get_user_by_github_id(99999) == nil
    end
  end
end