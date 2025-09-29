defmodule Gitclass.JobsTest do
  use Gitclass.DataCase

  alias Gitclass.Jobs
  alias Gitclass.Jobs.BackgroundJob

  import Gitclass.AccountsFixtures
  import Gitclass.ClassroomFixtures

  describe "background jobs" do
    test "create_background_job/1 creates a job with valid data" do
      teacher = user_fixture()
      class = class_fixture(%{teacher_id: teacher.id})

      valid_attrs = %{
        class_id: class.id,
        job_type: "import_students",
        total: 10
      }

      assert {:ok, %BackgroundJob{} = job} = Jobs.create_background_job(valid_attrs)
      assert job.class_id == class.id
      assert job.job_type == "import_students"
      assert job.status == "queued"
      assert job.progress == 0
      assert job.total == 10
    end

    test "create_background_job/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Jobs.create_background_job(%{job_type: nil})
    end

    test "get_background_job!/1 returns the job with given id" do
      job = background_job_fixture()
      assert Jobs.get_background_job!(job.id) == job
    end

    test "list_background_jobs_for_class/1 returns jobs for specific class" do
      teacher = user_fixture()
      class1 = class_fixture(%{teacher_id: teacher.id})
      class2 = class_fixture(%{teacher_id: teacher.id})

      job1 = background_job_fixture(%{class_id: class1.id})
      _job2 = background_job_fixture(%{class_id: class2.id})

      jobs = Jobs.list_background_jobs_for_class(class1.id)
      assert length(jobs) == 1
      assert hd(jobs).id == job1.id
    end

    test "list_active_jobs/0 returns only queued and running jobs" do
      _completed_job = background_job_fixture(%{status: "completed"})
      _failed_job = background_job_fixture(%{status: "failed"})
      queued_job = background_job_fixture(%{status: "queued"})
      running_job = background_job_fixture(%{status: "running"})

      active_jobs = Jobs.list_active_jobs()
      job_ids = Enum.map(active_jobs, & &1.id)

      assert queued_job.id in job_ids
      assert running_job.id in job_ids
      assert length(active_jobs) == 2
    end

    test "start_job/1 updates job status to running" do
      job = background_job_fixture()

      assert {:ok, updated_job} = Jobs.start_job(job)
      assert updated_job.status == "running"
      assert updated_job.started_at != nil
    end

    test "complete_job/1 updates job status to completed" do
      job = background_job_fixture(%{total: 5})

      assert {:ok, updated_job} = Jobs.complete_job(job)
      assert updated_job.status == "completed"
      assert updated_job.completed_at != nil
      assert updated_job.progress == 5
    end

    test "fail_job/2 updates job status to failed with error message" do
      job = background_job_fixture()
      error_message = "API rate limit exceeded"

      assert {:ok, updated_job} = Jobs.fail_job(job, error_message)
      assert updated_job.status == "failed"
      assert updated_job.completed_at != nil
      assert updated_job.error_message == error_message
    end

    test "update_job_progress/2 updates job progress" do
      job = background_job_fixture(%{total: 10})

      assert {:ok, updated_job} = Jobs.update_job_progress(job, 7)
      assert updated_job.progress == 7
    end

    test "get_job_stats/0 returns job statistics" do
      # Create jobs with different statuses
      _queued_job = background_job_fixture(%{status: "queued"})
      _running_job = background_job_fixture(%{status: "running"})
      _completed_job = background_job_fixture(%{status: "completed"})
      _failed_job = background_job_fixture(%{status: "failed"})

      stats = Jobs.get_job_stats()

      assert stats.by_status["queued"] >= 1
      assert stats.by_status["running"] >= 1
      assert stats.by_status["completed"] >= 1
      assert stats.by_status["failed"] >= 1
      assert is_number(stats.recent_failures)
      assert is_number(stats.avg_duration_seconds)
    end

    test "get_recent_job_activity/1 returns recent jobs" do
      # Create some jobs
      _job1 = background_job_fixture(%{job_type: "test1"})
      _job2 = background_job_fixture(%{job_type: "test2"})
      _job3 = background_job_fixture(%{job_type: "test3"})

      recent_jobs = Jobs.get_recent_job_activity(2)

      # Should return 2 jobs (limited by the parameter)
      assert length(recent_jobs) == 2

      # Should return BackgroundJob structs
      assert Enum.all?(recent_jobs, fn job ->
        match?(%BackgroundJob{}, job)
      end)
    end
  end

  defp background_job_fixture(attrs \\ %{}) do
    teacher = user_fixture()
    class = class_fixture(%{teacher_id: teacher.id})

    {:ok, job} =
      attrs
      |> Enum.into(%{
        class_id: class.id,
        job_type: "test_job",
        status: "queued",
        progress: 0,
        total: 1
      })
      |> Jobs.create_background_job()

    job
  end
end
