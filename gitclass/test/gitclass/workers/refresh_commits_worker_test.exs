defmodule Gitclass.Workers.RefreshCommitsWorkerTest do
  use Gitclass.DataCase, async: false
  use Oban.Testing, repo: Gitclass.Repo

  import Mox

  alias Gitclass.{Classroom, Accounts}
  alias Gitclass.Workers.RefreshCommitsWorker

  setup :verify_on_exit!

  describe "execute/1 - RefreshCommitsWorker" do
    setup do
      # Create a teacher and class for testing
      {:ok, teacher} = Accounts.create_user(%{
        github_id: 12345,
        github_username: "testteacher",
        name: "Test Teacher"
      })

      {:ok, class} = Classroom.create_class(teacher, %{
        name: "JavaScript 101",
        term: "Fall 2024"
      })

      # Add some students to the class
      {:ok, student1} = Classroom.add_student_to_class(class, "octocat", %{
        student_name: "Octocat",
        student_avatar_url: "https://github.com/images/error/octocat_happy.gif"
      })

      {:ok, student2} = Classroom.add_student_to_class(class, "torvalds", %{
        student_name: "Linus Torvalds",
        student_avatar_url: "https://avatars.githubusercontent.com/u/1024025"
      })

      %{class: class, teacher: teacher, student1: student1, student2: student2}
    end

    test "refreshes commits for a specific class", %{class: class} do
      # Mock GitHub API responses for commit fetching
      Gitclass.GitHubMock
      |> expect(:fetch_recent_commits, fn "octocat", 5 ->
        {:ok, mock_commits("octocat", 3)}
      end)
      |> expect(:fetch_recent_commits, fn "torvalds", 5 ->
        {:ok, mock_commits("torvalds", 5)}
      end)

      # Subscribe to PubSub updates
      Phoenix.PubSub.subscribe(Gitclass.PubSub, "class:#{class.id}:commits")
      Phoenix.PubSub.subscribe(Gitclass.PubSub, "class:#{class.id}:students")

      # Create and perform the job
      job = RefreshCommitsWorker.new(%{"class_id" => class.id})

      assert {:ok, :completed} = perform_job(RefreshCommitsWorker, job)

      # Verify PubSub notifications were sent
      assert_receive {:job_progress, %{type: :commit_update, username: "octocat", commit_count: 3}}
      assert_receive {:job_progress, %{type: :commit_update, username: "torvalds", commit_count: 5}}
      assert_receive {:job_progress, %{type: :refresh_completed, student_count: 2}}

      # Verify commit activities were stored
      date_range = Date.add(Date.utc_today(), -5)..Date.utc_today()
      octocat_commits = Classroom.get_commit_activities(class.id, "octocat", date_range)
      assert length(octocat_commits) > 0

      torvalds_commits = Classroom.get_commit_activities(class.id, "torvalds", date_range)
      assert length(torvalds_commits) > 0
    end

    test "refreshes all active classes when no class_id provided", %{class: class} do
      # Create another class with students
      {:ok, teacher2} = Accounts.create_user(%{
        github_id: 67890,
        github_username: "testteacher2",
        name: "Test Teacher 2"
      })

      {:ok, class2} = Classroom.create_class(teacher2, %{
        name: "Python 101",
        term: "Fall 2024"
      })

      {:ok, _student3} = Classroom.add_student_to_class(class2, "gvanrossum", %{
        student_name: "Guido van Rossum",
        student_avatar_url: "https://avatars.githubusercontent.com/u/2894642"
      })

      # Mock GitHub API responses for all students
      Gitclass.GitHubMock
      |> expect(:fetch_recent_commits, fn "octocat", 5 ->
        {:ok, mock_commits("octocat", 2)}
      end)
      |> expect(:fetch_recent_commits, fn "torvalds", 5 ->
        {:ok, mock_commits("torvalds", 3)}
      end)
      |> expect(:fetch_recent_commits, fn "gvanrossum", 5 ->
        {:ok, mock_commits("gvanrossum", 1)}
      end)

      # Create and perform the job without class_id
      job = RefreshCommitsWorker.new(%{})

      assert {:ok, results} = perform_job(RefreshCommitsWorker, job)

      # Verify both classes were processed
      assert results.successful == 2
      assert results.failed == 0
    end

    test "handles class with no students gracefully", %{teacher: teacher} do
      # Create a class with no students
      {:ok, empty_class} = Classroom.create_class(teacher, %{
        name: "Empty Class",
        term: "Fall 2024"
      })

      job = RefreshCommitsWorker.new(%{"class_id" => empty_class.id})

      assert {:ok, :no_students} = perform_job(RefreshCommitsWorker, job)
    end

    test "handles GitHub API rate limiting gracefully", %{class: class} do
      # Mock rate limit error
      Gitclass.GitHubMock
      |> expect(:fetch_recent_commits, fn "octocat", 5 ->
        {:error, :rate_limited}
      end)
      |> expect(:fetch_recent_commits, fn "torvalds", 5 ->
        {:ok, mock_commits("torvalds", 2)}
      end)

      job = RefreshCommitsWorker.new(%{"class_id" => class.id})

      # Should raise rate_limited error which will be handled by base worker
      assert_raise MatchError, fn ->
        perform_job(RefreshCommitsWorker, job)
      end
    end

    test "handles network errors for individual students", %{class: class} do
      # Mock network error for one student
      Gitclass.GitHubMock
      |> expect(:fetch_recent_commits, fn "octocat", 5 ->
        {:error, :network_error}
      end)
      |> expect(:fetch_recent_commits, fn "torvalds", 5 ->
        {:ok, mock_commits("torvalds", 4)}
      end)

      job = RefreshCommitsWorker.new(%{"class_id" => class.id})

      # Should complete despite one failure
      assert {:ok, :completed} = perform_job(RefreshCommitsWorker, job)

      # Verify the successful student's commits were stored
      date_range = Date.add(Date.utc_today(), -5)..Date.utc_today()
      torvalds_commits = Classroom.get_commit_activities(class.id, "torvalds", date_range)
      assert length(torvalds_commits) > 0
    end

    test "updates student last_commit_at timestamp", %{class: class, student1: student1} do
      recent_datetime = DateTime.utc_now() |> DateTime.add(-3600, :second) # 1 hour ago

      # Mock commits with recent timestamp
      Gitclass.GitHubMock
      |> expect(:fetch_recent_commits, fn "octocat", 5 ->
        {:ok, [
          %{
            sha: "abc123",
            message: "Test commit",
            author: "Octocat",
            date: DateTime.to_iso8601(recent_datetime),
            repository: "test-repo",
            html_url: "https://github.com/octocat/test-repo/commit/abc123"
          }
        ]}
      end)
      |> expect(:fetch_recent_commits, fn "torvalds", 5 ->
        {:ok, []}
      end)

      job = RefreshCommitsWorker.new(%{"class_id" => class.id})

      assert {:ok, :completed} = perform_job(RefreshCommitsWorker, job)

      # Verify student's last_commit_at was updated
      updated_student = Repo.get(Gitclass.Classroom.ClassStudent, student1.id)
      assert updated_student.last_commit_at != nil

      # Should be within a few seconds of our mocked time
      assert DateTime.diff(updated_student.last_commit_at, recent_datetime, :second) |> abs() < 5
    end

    test "stores commit activities grouped by date and repository", %{class: class} do
      today = Date.utc_today()
      yesterday = Date.add(today, -1)

      # Mock commits across different days and repos
      Gitclass.GitHubMock
      |> expect(:fetch_recent_commits, fn "octocat", 5 ->
        {:ok, [
          %{
            sha: "abc123",
            message: "Commit 1",
            author: "Octocat",
            date: DateTime.to_iso8601(DateTime.new!(today, ~T[10:00:00], "Etc/UTC")),
            repository: "repo-a",
            html_url: "https://github.com/octocat/repo-a/commit/abc123"
          },
          %{
            sha: "def456",
            message: "Commit 2",
            author: "Octocat",
            date: DateTime.to_iso8601(DateTime.new!(today, ~T[14:00:00], "Etc/UTC")),
            repository: "repo-a",
            html_url: "https://github.com/octocat/repo-a/commit/def456"
          },
          %{
            sha: "ghi789",
            message: "Commit 3",
            author: "Octocat",
            date: DateTime.to_iso8601(DateTime.new!(yesterday, ~T[12:00:00], "Etc/UTC")),
            repository: "repo-b",
            html_url: "https://github.com/octocat/repo-b/commit/ghi789"
          }
        ]}
      end)
      |> expect(:fetch_recent_commits, fn "torvalds", 5 ->
        {:ok, []}
      end)

      job = RefreshCommitsWorker.new(%{"class_id" => class.id})

      assert {:ok, :completed} = perform_job(RefreshCommitsWorker, job)

      # Verify commit activities were grouped correctly
      date_range = Date.add(Date.utc_today(), -5)..Date.utc_today()
      activities = Classroom.get_commit_activities(class.id, "octocat", date_range)

      # Should have 2 activities: today/repo-a (2 commits) and yesterday/repo-b (1 commit)
      assert length(activities) == 2

      today_activity = Enum.find(activities, fn a -> a.commit_date == today end)
      assert today_activity != nil
      assert today_activity.commit_count == 2
      assert today_activity.repository_name == "repo-a"

      yesterday_activity = Enum.find(activities, fn a -> a.commit_date == yesterday end)
      assert yesterday_activity != nil
      assert yesterday_activity.commit_count == 1
      assert yesterday_activity.repository_name == "repo-b"
    end

    test "processes students in batches with delay", %{class: class} do
      # Add more students to test batching (5 at a time with 1s delay)
      for i <- 3..7 do
        {:ok, _} = Classroom.add_student_to_class(class, "user#{i}", %{
          student_name: "User #{i}",
          student_avatar_url: "https://avatars.githubusercontent.com/u/#{i}"
        })
      end

      # Mock responses for all students
      for i <- 0..7 do
        username = if i < 2, do: ["octocat", "torvalds"] |> Enum.at(i), else: "user#{i}"

        Gitclass.GitHubMock
        |> expect(:fetch_recent_commits, fn ^username, 5 ->
          {:ok, mock_commits(username, 1)}
        end)
      end

      job = RefreshCommitsWorker.new(%{"class_id" => class.id})

      start_time = System.monotonic_time(:millisecond)
      assert {:ok, :completed} = perform_job(RefreshCommitsWorker, job)
      end_time = System.monotonic_time(:millisecond)

      # With 7 students in batches of 5, we should have at least 1 second delay
      # (after first batch of 5, before second batch of 2)
      duration = end_time - start_time
      assert duration >= 1000  # At least 1 second
    end
  end

  # Helper functions

  defp mock_commits(username, count) do
    for i <- 1..count do
      days_ago = rem(i, 5)
      date = Date.utc_today() |> Date.add(-days_ago)
      datetime = DateTime.new!(date, ~T[12:00:00], "Etc/UTC")

      %{
        sha: "#{username}_commit_#{i}",
        message: "Test commit #{i} by #{username}",
        author: username,
        date: DateTime.to_iso8601(datetime),
        repository: "test-repo-#{rem(i, 2)}",
        html_url: "https://github.com/#{username}/test-repo/commit/#{username}_commit_#{i}"
      }
    end
  end
end