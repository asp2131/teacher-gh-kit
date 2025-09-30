defmodule Gitclass.Workers.VerifyPagesRepoWorkerTest do
  use Gitclass.DataCase, async: false
  use Oban.Testing, repo: Gitclass.Repo

  import Mox

  alias Gitclass.{Classroom, Accounts}
  alias Gitclass.Workers.VerifyPagesRepoWorker

  setup :verify_on_exit!

  describe "execute/1 - VerifyPagesRepoWorker" do
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

      # Add a student to the class
      {:ok, student} = Classroom.add_student_to_class(class, "octocat", %{
        student_name: "Octocat",
        student_avatar_url: "https://github.com/images/error/octocat_happy.gif"
      })

      %{class: class, teacher: teacher, student: student}
    end

    test "successfully verifies existing GitHub Pages repository", %{class: class, student: student} do
      repo_data = %{
        exists: true,
        name: "octocat.github.io",
        full_name: "octocat/octocat.github.io",
        html_url: "https://github.com/octocat/octocat.github.io",
        clone_url: "https://github.com/octocat/octocat.github.io.git",
        pages_url: "https://octocat.github.io",
        private: false,
        created_at: "2020-01-01T00:00:00Z",
        updated_at: "2024-01-01T00:00:00Z",
        pushed_at: "2024-01-15T00:00:00Z"
      }

      # Mock GitHub API response
      Gitclass.GitHubMock
      |> expect(:check_pages_repository, fn "octocat" ->
        {:ok, repo_data}
      end)

      # Subscribe to PubSub updates
      Phoenix.PubSub.subscribe(Gitclass.PubSub, "class:#{class.id}:students")

      # Create and perform the job
      job = VerifyPagesRepoWorker.new(%{
        "class_id" => class.id,
        "username" => "octocat"
      })

      assert {:ok, :verified} = perform_job(VerifyPagesRepoWorker, job)

      # Verify PubSub notification was sent
      assert_receive {:job_progress, %{
        type: :pages_repo_update,
        username: "octocat",
        status: :verified
      }}

      # Verify student record was updated
      updated_student = Repo.get(Gitclass.Classroom.ClassStudent, student.id)
      assert updated_student.has_pages_repo == true
      assert updated_student.pages_repo_url == "https://github.com/octocat/octocat.github.io"
      assert updated_student.live_site_url == "https://octocat.github.io"
      assert updated_student.verification_status == "verified"
    end

    test "handles missing GitHub Pages repository", %{class: class, student: student} do
      repo_data = %{
        exists: false,
        pages_url: "https://octocat.github.io"
      }

      # Mock GitHub API response for missing repo
      Gitclass.GitHubMock
      |> expect(:check_pages_repository, fn "octocat" ->
        {:ok, repo_data}
      end)

      # Subscribe to PubSub updates
      Phoenix.PubSub.subscribe(Gitclass.PubSub, "class:#{class.id}:students")

      # Create and perform the job
      job = VerifyPagesRepoWorker.new(%{
        "class_id" => class.id,
        "username" => "octocat"
      })

      assert {:ok, :missing} = perform_job(VerifyPagesRepoWorker, job)

      # Verify PubSub notification was sent
      assert_receive {:job_progress, %{
        type: :pages_repo_update,
        username: "octocat",
        status: :missing
      }}

      # Verify student record was updated
      updated_student = Repo.get(Gitclass.Classroom.ClassStudent, student.id)
      assert updated_student.has_pages_repo == false
      assert updated_student.pages_repo_url == nil
      assert updated_student.live_site_url == "https://octocat.github.io"
      assert updated_student.verification_status == "missing"
    end

    test "handles GitHub API rate limiting", %{class: class} do
      # Mock rate limit error
      Gitclass.GitHubMock
      |> expect(:check_pages_repository, fn "octocat" ->
        {:error, :rate_limited}
      end)

      job = VerifyPagesRepoWorker.new(%{
        "class_id" => class.id,
        "username" => "octocat"
      })

      # Should raise rate_limited error which will be caught by base worker
      assert_raise MatchError, fn ->
        perform_job(VerifyPagesRepoWorker, job)
      end
    end

    test "handles GitHub API network errors", %{class: class} do
      # Mock network error
      Gitclass.GitHubMock
      |> expect(:check_pages_repository, fn "octocat" ->
        {:error, :network_error}
      end)

      # Subscribe to PubSub updates
      Phoenix.PubSub.subscribe(Gitclass.PubSub, "class:#{class.id}:students")

      job = VerifyPagesRepoWorker.new(%{
        "class_id" => class.id,
        "username" => "octocat"
      })

      assert {:error, :network_error} = perform_job(VerifyPagesRepoWorker, job)

      # Verify error notification was sent
      assert_receive {:job_progress, %{
        type: :pages_repo_update,
        username: "octocat",
        status: :error,
        data: %{error: :network_error}
      }}
    end

    test "handles unauthorized GitHub API errors", %{class: class} do
      # Mock unauthorized error
      Gitclass.GitHubMock
      |> expect(:check_pages_repository, fn "octocat" ->
        {:error, :unauthorized}
      end)

      # Subscribe to PubSub updates
      Phoenix.PubSub.subscribe(Gitclass.PubSub, "class:#{class.id}:students")

      job = VerifyPagesRepoWorker.new(%{
        "class_id" => class.id,
        "username" => "octocat"
      })

      assert {:error, :unauthorized} = perform_job(VerifyPagesRepoWorker, job)

      # Verify error notification was sent
      assert_receive {:job_progress, %{
        type: :pages_repo_update,
        username: "octocat",
        status: :error
      }}
    end

    test "handles student not found in class", %{class: class} do
      repo_data = %{
        exists: true,
        name: "nonexistent.github.io",
        full_name: "nonexistent/nonexistent.github.io",
        html_url: "https://github.com/nonexistent/nonexistent.github.io",
        clone_url: "https://github.com/nonexistent/nonexistent.github.io.git",
        pages_url: "https://nonexistent.github.io",
        private: false,
        created_at: "2020-01-01T00:00:00Z",
        updated_at: "2024-01-01T00:00:00Z",
        pushed_at: "2024-01-15T00:00:00Z"
      }

      # Mock GitHub API response
      Gitclass.GitHubMock
      |> expect(:check_pages_repository, fn "nonexistent" ->
        {:ok, repo_data}
      end)

      job = VerifyPagesRepoWorker.new(%{
        "class_id" => class.id,
        "username" => "nonexistent"
      })

      # Should still complete successfully even though student not in DB
      assert {:ok, :verified} = perform_job(VerifyPagesRepoWorker, job)
    end

    test "verifies private repository correctly", %{class: class, student: student} do
      repo_data = %{
        exists: true,
        name: "octocat.github.io",
        full_name: "octocat/octocat.github.io",
        html_url: "https://github.com/octocat/octocat.github.io",
        clone_url: "https://github.com/octocat/octocat.github.io.git",
        pages_url: "https://octocat.github.io",
        private: true,  # Repository is private
        created_at: "2020-01-01T00:00:00Z",
        updated_at: "2024-01-01T00:00:00Z",
        pushed_at: "2024-01-15T00:00:00Z"
      }

      # Mock GitHub API response
      Gitclass.GitHubMock
      |> expect(:check_pages_repository, fn "octocat" ->
        {:ok, repo_data}
      end)

      job = VerifyPagesRepoWorker.new(%{
        "class_id" => class.id,
        "username" => "octocat"
      })

      assert {:ok, :verified} = perform_job(VerifyPagesRepoWorker, job)

      # Verify student record shows repo exists (even if private)
      updated_student = Repo.get(Gitclass.Classroom.ClassStudent, student.id)
      assert updated_student.has_pages_repo == true
      assert updated_student.verification_status == "verified"
    end

    test "updates existing verification status", %{class: class, student: student} do
      # First, set the student as having a verified repo
      {:ok, _} = Classroom.update_class_student(student, %{
        has_pages_repo: true,
        pages_repo_url: "https://github.com/octocat/octocat.github.io",
        live_site_url: "https://octocat.github.io",
        verification_status: "verified"
      })

      # Now the repo is missing
      repo_data = %{
        exists: false,
        pages_url: "https://octocat.github.io"
      }

      # Mock GitHub API response
      Gitclass.GitHubMock
      |> expect(:check_pages_repository, fn "octocat" ->
        {:ok, repo_data}
      end)

      job = VerifyPagesRepoWorker.new(%{
        "class_id" => class.id,
        "username" => "octocat"
      })

      assert {:ok, :missing} = perform_job(VerifyPagesRepoWorker, job)

      # Verify student record was updated to missing
      updated_student = Repo.get(Gitclass.Classroom.ClassStudent, student.id)
      assert updated_student.has_pages_repo == false
      assert updated_student.pages_repo_url == nil
      assert updated_student.verification_status == "missing"
    end

    test "broadcasts correct data structure in PubSub messages", %{class: class} do
      repo_data = %{
        exists: true,
        name: "octocat.github.io",
        full_name: "octocat/octocat.github.io",
        html_url: "https://github.com/octocat/octocat.github.io",
        clone_url: "https://github.com/octocat/octocat.github.io.git",
        pages_url: "https://octocat.github.io",
        private: false,
        created_at: "2020-01-01T00:00:00Z",
        updated_at: "2024-01-01T00:00:00Z",
        pushed_at: "2024-01-15T00:00:00Z"
      }

      # Mock GitHub API response
      Gitclass.GitHubMock
      |> expect(:check_pages_repository, fn "octocat" ->
        {:ok, repo_data}
      end)

      # Subscribe to PubSub updates
      Phoenix.PubSub.subscribe(Gitclass.PubSub, "class:#{class.id}:students")

      job = VerifyPagesRepoWorker.new(%{
        "class_id" => class.id,
        "username" => "octocat"
      })

      assert {:ok, :verified} = perform_job(VerifyPagesRepoWorker, job)

      # Verify PubSub message structure
      assert_receive {:job_progress, message}

      assert message.type == :pages_repo_update
      assert message.username == "octocat"
      assert message.status == :verified
      assert is_map(message.data)
      assert message.data.exists == true
      assert message.data.pages_url == "https://octocat.github.io"
    end

    test "handles concurrent verification jobs for different students", %{class: class} do
      # Add another student
      {:ok, _student2} = Classroom.add_student_to_class(class, "torvalds", %{
        student_name: "Linus Torvalds",
        student_avatar_url: "https://avatars.githubusercontent.com/u/1024025"
      })

      # Mock responses for both students
      Gitclass.GitHubMock
      |> expect(:check_pages_repository, fn "octocat" ->
        {:ok, %{
          exists: true,
          name: "octocat.github.io",
          full_name: "octocat/octocat.github.io",
          html_url: "https://github.com/octocat/octocat.github.io",
          clone_url: "https://github.com/octocat/octocat.github.io.git",
          pages_url: "https://octocat.github.io",
          private: false,
          created_at: "2020-01-01T00:00:00Z",
          updated_at: "2024-01-01T00:00:00Z",
          pushed_at: "2024-01-15T00:00:00Z"
        }}
      end)
      |> expect(:check_pages_repository, fn "torvalds" ->
        {:ok, %{exists: false, pages_url: "https://torvalds.github.io"}}
      end)

      # Create and perform jobs for both students
      job1 = VerifyPagesRepoWorker.new(%{
        "class_id" => class.id,
        "username" => "octocat"
      })

      job2 = VerifyPagesRepoWorker.new(%{
        "class_id" => class.id,
        "username" => "torvalds"
      })

      assert {:ok, :verified} = perform_job(VerifyPagesRepoWorker, job1.args)
      assert {:ok, :missing} = perform_job(VerifyPagesRepoWorker, job2.args)

      # Verify both students were updated correctly
      octocat_student = Classroom.get_class_student(class.id, "octocat")
      assert octocat_student.has_pages_repo == true
      assert octocat_student.verification_status == "verified"

      torvalds_student = Classroom.get_class_student(class.id, "torvalds")
      assert torvalds_student.has_pages_repo == false
      assert torvalds_student.verification_status == "missing"
    end
  end
end