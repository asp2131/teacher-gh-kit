defmodule Gitclass.GitHubTest do
  use ExUnit.Case, async: true

  alias Gitclass.GitHub

  describe "valid_username?/1" do
    test "returns true for valid usernames" do
      assert GitHub.valid_username?("octocat")
      assert GitHub.valid_username?("test-user")
      assert GitHub.valid_username?("user123")
      assert GitHub.valid_username?("a")
      assert GitHub.valid_username?("a-b-c")
    end

    test "returns false for invalid usernames" do
      refute GitHub.valid_username?("-invalid")
      refute GitHub.valid_username?("invalid-")
      refute GitHub.valid_username?("invalid--user")
      refute GitHub.valid_username?("")
      refute GitHub.valid_username?(nil)
      refute GitHub.valid_username?(123)
      refute GitHub.valid_username?("user@domain")
      refute GitHub.valid_username?("user.name")
    end

    test "returns false for usernames that are too long" do
      long_username = String.duplicate("a", 40)
      refute GitHub.valid_username?(long_username)
    end
  end

  describe "fetch_user_profile/1" do
    test "validates username format before making request" do
      assert {:error, :invalid_username} = GitHub.fetch_user_profile("-invalid")
      assert {:error, :invalid_username} = GitHub.fetch_user_profile("")
    end
  end

  describe "check_pages_repository/1" do
    test "validates username format before making request" do
      assert {:error, :invalid_username} = GitHub.check_pages_repository("-invalid")
      assert {:error, :invalid_username} = GitHub.check_pages_repository("")
    end
  end

  describe "fetch_recent_commits/2" do
    test "validates username format before making request" do
      assert {:error, :invalid_username} = GitHub.fetch_recent_commits("-invalid")
      assert {:error, :invalid_username} = GitHub.fetch_recent_commits("")
    end

    test "validates days_back parameter" do
      assert {:error, :invalid_days} = GitHub.fetch_recent_commits("octocat", -1)
      assert {:error, :invalid_days} = GitHub.fetch_recent_commits("octocat", 0)
    end
  end

  describe "get_commit_calendar/2" do
    test "validates username format before making request" do
      date_range = Date.range(Date.utc_today() |> Date.add(-4), Date.utc_today())
      assert {:error, :invalid_username} = GitHub.get_commit_calendar("-invalid", date_range)
    end
  end
end