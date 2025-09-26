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
end