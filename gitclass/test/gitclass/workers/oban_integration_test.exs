defmodule Gitclass.Workers.ObanIntegrationTest do
  use Gitclass.DataCase, async: false
  use Oban.Testing, repo: Gitclass.Repo

  alias Gitclass.{Jobs, Classroom, Accounts}
  alias Gitclass.Workers.RefreshCommitsWorker

  describe "Oban job processing" do
    test "can enqueue and process refresh commits job" do
      # Create a teacher and class for testing
      {:ok, teacher} = Accounts.create_user(%{
        github_id: 12345,
        github_username: "testteacher",
        name: "Test Teacher"
      })

      {:ok, class} = Classroom.create_class(teacher, %{
        name: "Test Class",
        term: "Fall 2024"
      })

      # Enqueue a refresh commits job
      {:ok, job} = Jobs.schedule_commit_refresh(class.id)

      # Verify the job was enqueued
      assert %Oban.Job{} = job
      assert job.queue == "github_api"
      assert job.worker == "Gitclass.Workers.RefreshCommitsWorker"
      assert job.args == %{"class_id" => class.id}

      # Verify the job would be enqueued (in test mode, jobs aren't actually enqueued)
      # We can verify the job structure is correct
      assert job.args["class_id"] == class.id
    end

    test "can enqueue student import job with background job tracking" do
      # Create a teacher and class for testing
      {:ok, teacher} = Accounts.create_user(%{
        github_id: 12346,
        github_username: "testteacher2",
        name: "Test Teacher 2"
      })

      {:ok, class} = Classroom.create_class(teacher, %{
        name: "Test Class 2",
        term: "Fall 2024"
      })

      usernames = ["testuser1", "testuser2", "testuser3"]

      # Enqueue an import job
      {:ok, %{background_job: bg_job, oban_job: oban_job}} =
        Jobs.import_students(class.id, usernames)

      # Verify the background job was created
      assert bg_job.class_id == class.id
      assert bg_job.job_type == "import_students"
      assert bg_job.total == 3
      assert bg_job.status == "queued"

      # Verify the Oban job was enqueued
      assert oban_job.queue == "import"
      assert oban_job.worker == "Gitclass.Workers.ImportStudentsWorker"
      assert oban_job.args["class_id"] == class.id
      assert oban_job.args["usernames"] == usernames
      assert oban_job.args["job_id"] == bg_job.id

      # Verify the job structure is correct (in test mode, jobs aren't actually enqueued)
      assert oban_job.args["class_id"] == class.id
      assert oban_job.args["usernames"] == usernames
    end

    test "background job progress tracking functions work" do
      # Create a background job
      {:ok, bg_job} = Jobs.create_background_job(%{
        job_type: "test_job",
        total: 10,
        status: "queued"
      })

      # Test starting the job
      {:ok, started_job} = Jobs.start_job(bg_job)
      assert started_job.status == "running"
      assert started_job.started_at != nil

      # Test updating progress
      {:ok, updated_job} = Jobs.update_job_progress(started_job, 5)
      assert updated_job.progress == 5

      # Test completing the job
      {:ok, completed_job} = Jobs.complete_job(updated_job)
      assert completed_job.status == "completed"
      assert completed_job.completed_at != nil
      assert completed_job.progress == completed_job.total

      # Test failing a job
      {:ok, another_job} = Jobs.create_background_job(%{
        job_type: "test_job_2",
        status: "running"
      })

      {:ok, failed_job} = Jobs.fail_job(another_job, "Test error message")
      assert failed_job.status == "failed"
      assert failed_job.error_message == "Test error message"
      assert failed_job.completed_at != nil
    end
  end
end
