defmodule Gitclass.Jobs do
  @moduledoc """
  The Jobs context for managing background job tracking and progress.
  """

  import Ecto.Query, warn: false
  alias Gitclass.Repo
  alias Gitclass.Jobs.BackgroundJob

  @doc """
  Creates a background job record.
  """
  def create_background_job(attrs \\ %{}) do
    %BackgroundJob{}
    |> BackgroundJob.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a background job.
  """
  def update_background_job(%BackgroundJob{} = job, attrs) do
    job
    |> BackgroundJob.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Gets a background job by ID.
  """
  def get_background_job!(id), do: Repo.get!(BackgroundJob, id)

  @doc """
  Gets background jobs for a class.
  """
  def list_background_jobs_for_class(class_id) do
    BackgroundJob
    |> where([j], j.class_id == ^class_id)
    |> order_by([j], desc: j.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets active background jobs.
  """
  def list_active_jobs do
    BackgroundJob
    |> where([j], j.status in ["queued", "running"])
    |> Repo.all()
  end

  @doc """
  Marks a job as started.
  """
  def start_job(%BackgroundJob{} = job) do
    update_background_job(job, %{
      status: "running",
      started_at: DateTime.utc_now()
    })
  end

  @doc """
  Marks a job as completed.
  """
  def complete_job(%BackgroundJob{} = job) do
    update_background_job(job, %{
      status: "completed",
      completed_at: DateTime.utc_now(),
      progress: job.total
    })
  end

  @doc """
  Marks a job as failed.
  """
  def fail_job(%BackgroundJob{} = job, error_message) do
    update_background_job(job, %{
      status: "failed",
      completed_at: DateTime.utc_now(),
      error_message: error_message
    })
  end

  @doc """
  Updates job progress.
  """
  def update_job_progress(%BackgroundJob{} = job, progress) do
    update_background_job(job, %{progress: progress})
  end

  @doc """
  Cleans up old completed jobs (older than 7 days).
  """
  def cleanup_old_jobs do
    cutoff_date = DateTime.utc_now() |> DateTime.add(-7, :day)

    BackgroundJob
    |> where([j], j.status in ["completed", "failed"])
    |> where([j], j.completed_at < ^cutoff_date)
    |> Repo.delete_all()
  end

  @doc """
  Gets job statistics for monitoring.
  """
  def get_job_stats do
    stats =
      BackgroundJob
      |> group_by([j], j.status)
      |> select([j], {j.status, count(j.id)})
      |> Repo.all()
      |> Enum.into(%{})

    # Get failed jobs from last 24 hours
    yesterday = DateTime.utc_now() |> DateTime.add(-1, :day)

    recent_failures =
      BackgroundJob
      |> where([j], j.status == "failed")
      |> where([j], j.completed_at > ^yesterday)
      |> select([j], count(j.id))
      |> Repo.one()

    # Get average job duration for completed jobs
    avg_duration =
      BackgroundJob
      |> where([j], j.status == "completed")
      |> where([j], not is_nil(j.started_at) and not is_nil(j.completed_at))
      |> select([j], avg(fragment("EXTRACT(EPOCH FROM (? - ?))", j.completed_at, j.started_at)))
      |> Repo.one()

    %{
      by_status: stats,
      recent_failures: recent_failures || 0,
      avg_duration_seconds: if(avg_duration, do: Float.round(avg_duration, 2), else: 0)
    }
  end

  @doc """
  Gets recent job activity for monitoring dashboard.
  """
  def get_recent_job_activity(limit \\ 20) do
    BackgroundJob
    |> order_by([j], desc: j.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Gets a background job by ID.
  """
  def get_background_job(id) when is_binary(id) do
    case Repo.get(BackgroundJob, id) do
      nil -> {:error, :not_found}
      job -> {:ok, job}
    end
  end

  @doc """
  Enqueue a student import job.
  """
  def import_students(class_id, usernames) when is_binary(class_id) and is_list(usernames) do
    # Create background job record for tracking
    {:ok, bg_job} = create_background_job(%{
      class_id: class_id,
      job_type: "import_students",
      total: length(usernames),
      status: "queued"
    })

    # Enqueue Oban job
    %{
      class_id: class_id,
      usernames: usernames,
      job_id: bg_job.id
    }
    |> Gitclass.Workers.ImportStudentsWorker.new(queue: :import)
    |> Oban.insert()
    |> case do
      {:ok, oban_job} ->
        {:ok, %{background_job: bg_job, oban_job: oban_job}}

      {:error, changeset} ->
        # Clean up background job if Oban job failed to enqueue
        delete_background_job(bg_job)
        {:error, changeset}
    end
  end

  @doc """
  Schedule commit refresh for a specific class or all classes.
  """
  def schedule_commit_refresh(class_id \\ nil) do
    args = if class_id, do: %{class_id: class_id}, else: %{}

    args
    |> Gitclass.Workers.RefreshCommitsWorker.new(queue: :github_api)
    |> Oban.insert()
  end

  defp delete_background_job(%BackgroundJob{} = job) do
    Repo.delete(job)
  end
end
