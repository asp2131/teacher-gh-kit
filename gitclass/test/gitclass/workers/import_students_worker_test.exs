defmodule Gitclass.Workers.ImportStudentsWorkerTest do
  use Gitclass.DataCase, async: false
  use Oban.Testing, repo: Gitclass.Repo

  import Mox

  alias Gitclass.{Jobs, Classroom, Accounts}
  alias Gitclass.Workers.ImportStudentsWorker

  setup :verify_on_exit!

  describe "execute/1 - ImportStudentsWorker" do
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

      {:ok, bg_job} = Jobs.create_background_job(%{
        class_id: class.id,
        job_type: "import_students",
        total: 3,
        status: "queued"
      })

      %{class: class, teacher: teacher, bg_job: bg_job}
    end

    test "successfully imports students with valid GitHub usernames", %{class: class, bg_job: bg_job} do
      usernames = ["octocat", "torvalds", "defunkt"]

      # Mock successful GitHub API responses
      mock_github_responses(usernames)

      # Subscribe to PubSub updates
      Phoenix.PubSub.subscribe(Gitclass.PubSub, "class:#{class.id}:import")

      # Create and perform the job
      job = ImportStudentsWorker.new(%{
        "class_id" => class.id,
        "usernames" => usernames,
        "job_id" => bg_job.id
      })

      assert {:ok, result} = perform_job(ImportStudentsWorker, job)

      # Verify results
      assert result.successful == 3
      assert result.failed == 0
      assert length(result.results) == 3

      # Verify students were added to the database
      students = Classroom.list_class_students(class)
      assert length(students) == 3

      student_usernames = Enum.map(students, & &1.student_github_username)
      assert "octocat" in student_usernames
      assert "torvalds" in student_usernames
      assert "defunkt" in student_usernames

      # Verify PubSub notifications were sent
      assert_receive {:job_progress, %{status: :started}}
      assert_receive {:job_progress, %{status: :progress, current_student: "octocat"}}
      assert_receive {:job_progress, %{status: :progress, current_student: "torvalds"}}
      assert_receive {:job_progress, %{status: :progress, current_student: "defunkt"}}
      assert_receive {:job_progress, %{status: :completed, successful: 3, failed: 0}}

      # Verify background job was updated
      updated_bg_job = Repo.get(Gitclass.Jobs.BackgroundJob, bg_job.id)
      assert updated_bg_job.status == "completed"
    end

    test "handles mix of valid and invalid usernames", %{class: class, bg_job: bg_job} do
      usernames = ["octocat", "invalid-user-not-found", "torvalds"]

      # Mock GitHub API responses with one failure
      Gitclass.GitHubMock
      |> expect(:fetch_user_profile, fn "octocat" ->
        {:ok, mock_user_data("octocat")}
      end)
      |> expect(:fetch_user_profile, fn "invalid-user-not-found" ->
        {:error, :user_not_found}
      end)
      |> expect(:fetch_user_profile, fn "torvalds" ->
        {:ok, mock_user_data("torvalds")}
      end)

      job = ImportStudentsWorker.new(%{
        "class_id" => class.id,
        "usernames" => usernames,
        "job_id" => bg_job.id
      })

      assert {:ok, result} = perform_job(ImportStudentsWorker, job)

      # Verify results
      assert result.successful == 2
      assert result.failed == 1

      # Verify only valid users were added
      students = Classroom.list_class_students(class)
      assert length(students) == 2

      student_usernames = Enum.map(students, & &1.student_github_username)
      assert "octocat" in student_usernames
      assert "torvalds" in student_usernames
      refute "invalid-user-not-found" in student_usernames
    end

    test "handles GitHub API rate limiting", %{class: class, bg_job: bg_job} do
      usernames = ["octocat"]

      # Mock rate limit error
      Gitclass.GitHubMock
      |> expect(:fetch_user_profile, fn "octocat" ->
        {:error, :rate_limited}
      end)

      job = ImportStudentsWorker.new(%{
        "class_id" => class.id,
        "usernames" => usernames,
        "job_id" => bg_job.id
      })

      assert {:ok, result} = perform_job(ImportStudentsWorker, job)

      # Verify the error was handled
      assert result.successful == 0
      assert result.failed == 1
    end

    test "handles network errors gracefully", %{class: class, bg_job: bg_job} do
      usernames = ["octocat", "torvalds"]

      # Mock network error for first user, success for second
      Gitclass.GitHubMock
      |> expect(:fetch_user_profile, fn "octocat" ->
        {:error, :network_error}
      end)
      |> expect(:fetch_user_profile, fn "torvalds" ->
        {:ok, mock_user_data("torvalds")}
      end)

      job = ImportStudentsWorker.new(%{
        "class_id" => class.id,
        "usernames" => usernames,
        "job_id" => bg_job.id
      })

      assert {:ok, result} = perform_job(ImportStudentsWorker, job)

      # Verify partial success
      assert result.successful == 1
      assert result.failed == 1

      students = Classroom.list_class_students(class)
      assert length(students) == 1
      assert hd(students).student_github_username == "torvalds"
    end

    test "handles empty username list", %{class: class, bg_job: bg_job} do
      job = ImportStudentsWorker.new(%{
        "class_id" => class.id,
        "usernames" => [],
        "job_id" => bg_job.id
      })

      assert {:ok, result} = perform_job(ImportStudentsWorker, job)

      assert result.successful == 0
      assert result.failed == 0
      assert result.results == []
    end

    test "handles duplicate usernames in the same class", %{class: class, bg_job: bg_job} do
      # First, add a student manually
      {:ok, _} = Classroom.add_student_to_class(class, "octocat", %{
        student_name: "Octocat",
        student_avatar_url: "https://github.com/images/error/octocat_happy.gif"
      })

      # Try to import the same student again
      usernames = ["octocat"]

      Gitclass.GitHubMock
      |> expect(:fetch_user_profile, fn "octocat" ->
        {:ok, mock_user_data("octocat")}
      end)

      job = ImportStudentsWorker.new(%{
        "class_id" => class.id,
        "usernames" => usernames,
        "job_id" => bg_job.id
      })

      assert {:ok, result} = perform_job(ImportStudentsWorker, job)

      # Should handle duplicate gracefully (error adding to class)
      assert result.successful == 0
      assert result.failed == 1

      # Still only one student in the class
      students = Classroom.list_class_students(class)
      assert length(students) == 1
    end

    test "triggers GitHub Pages repository verification for each student", %{class: class, bg_job: bg_job} do
      usernames = ["octocat"]

      mock_github_responses(usernames)

      job = ImportStudentsWorker.new(%{
        "class_id" => class.id,
        "usernames" => usernames,
        "job_id" => bg_job.id
      })

      assert {:ok, _result} = perform_job(ImportStudentsWorker, job)

      # Verify that a VerifyPagesRepoWorker job was enqueued
      # In test mode, we can check if jobs were scheduled
      assert_enqueued worker: Gitclass.Workers.VerifyPagesRepoWorker,
                      args: %{class_id: class.id, username: "octocat"}
    end
  end

  # Helper functions

  defp mock_github_responses(usernames) do
    Enum.each(usernames, fn username ->
      Gitclass.GitHubMock
      |> expect(:fetch_user_profile, fn ^username ->
        {:ok, mock_user_data(username)}
      end)
    end)
  end

  defp mock_user_data(username) do
    %{
      id: :rand.uniform(1_000_000),
      login: username,
      name: "#{username} Name",
      avatar_url: "https://avatars.githubusercontent.com/u/#{:rand.uniform(1_000_000)}",
      email: "#{username}@example.com",
      public_repos: :rand.uniform(100),
      followers: :rand.uniform(1000),
      following: :rand.uniform(500),
      created_at: "2020-01-01T00:00:00Z"
    }
  end
end