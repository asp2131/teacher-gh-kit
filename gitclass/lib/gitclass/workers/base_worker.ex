defmodule Gitclass.Workers.BaseWorker do
  @moduledoc """
  Base worker module with common error handling and retry logic.
  """

  defmacro __using__(opts) do
    quote do
      use Oban.Worker, unquote(opts)

      import Gitclass.Workers.BaseWorker
      require Logger

      @impl Oban.Worker
      def perform(%Oban.Job{} = job) do
        job_name = __MODULE__ |> Module.split() |> List.last()
        Logger.info("Starting job: #{job_name} with args: #{inspect(job.args)}")

        start_time = System.monotonic_time(:millisecond)

        try do
          result = execute(job)

          duration = System.monotonic_time(:millisecond) - start_time
          Logger.info("Completed job: #{job_name} in #{duration}ms")

          result
        rescue
          error ->
            duration = System.monotonic_time(:millisecond) - start_time
            Logger.error("Job failed: #{job_name} after #{duration}ms - #{inspect(error)}")

            handle_error(error, job)
        end
      end

      # Override this function in your worker
      def execute(%Oban.Job{} = job) do
        raise "execute/1 must be implemented in #{__MODULE__}"
      end

      # Override this function for custom error handling
      def handle_error(error, %Oban.Job{} = job) do
        Gitclass.Workers.BaseWorker.default_error_handler(error, job)
      end

      defoverridable execute: 1, handle_error: 2
    end
  end

  @doc """
  Default error handler with retry logic based on error type.
  """
  def default_error_handler(error, %Oban.Job{} = job) do
    require Logger
    case error do
      # Network errors - retry with backoff
      %{reason: :network_error} ->
        {:snooze, calculate_backoff(job.attempt)}

      # Rate limiting - retry after delay
      %{reason: :rate_limited} ->
        {:snooze, 60}  # Wait 1 minute for rate limit reset

      # Invalid data - don't retry
      %{reason: :invalid_username} ->
        {:discard, "Invalid username provided"}

      %{reason: :user_not_found} ->
        {:discard, "GitHub user not found"}

      # Generic errors - retry with exponential backoff
      _ ->
        if job.attempt >= 3 do
          {:discard, "Max retries exceeded: #{inspect(error)}"}
        else
          {:snooze, calculate_backoff(job.attempt)}
        end
    end
  end

  @doc """
  Calculate exponential backoff delay in seconds.
  """
  def calculate_backoff(attempt) do
    # Exponential backoff: 2^attempt seconds, with jitter
    base_delay = :math.pow(2, attempt) |> round()
    jitter = :rand.uniform(base_delay)
    base_delay + jitter
  end

  @doc """
  Broadcast job progress updates via PubSub.
  """
  def broadcast_progress(topic, progress_data) do
    Phoenix.PubSub.broadcast(
      Gitclass.PubSub,
      topic,
      {:job_progress, progress_data}
    )
  end

  @doc """
  Update background job progress in database.
  """
  def update_job_progress(job_id, progress, total \\ nil) when is_binary(job_id) do
    require Logger
    case Gitclass.Jobs.get_background_job(job_id) do
      {:ok, bg_job} ->
        updates = %{progress: progress}
        updates = if total, do: Map.put(updates, :total, total), else: updates

        Gitclass.Jobs.update_background_job(bg_job, updates)

      {:error, _} ->
        Logger.warning("Could not find background job with ID: #{job_id}")
        :ok
    end
  end

  @doc """
  Mark background job as started.
  """
  def start_background_job(job_id) when is_binary(job_id) do
    require Logger
    case Gitclass.Jobs.get_background_job(job_id) do
      {:ok, bg_job} ->
        Gitclass.Jobs.start_job(bg_job)

      {:error, _} ->
        Logger.warning("Could not find background job with ID: #{job_id}")
        :ok
    end
  end

  @doc """
  Mark background job as completed.
  """
  def complete_background_job(job_id) when is_binary(job_id) do
    require Logger
    case Gitclass.Jobs.get_background_job(job_id) do
      {:ok, bg_job} ->
        Gitclass.Jobs.complete_job(bg_job)

      {:error, _} ->
        Logger.warning("Could not find background job with ID: #{job_id}")
        :ok
    end
  end

  @doc """
  Mark background job as failed.
  """
  def fail_background_job(job_id, error_message) when is_binary(job_id) do
    require Logger
    case Gitclass.Jobs.get_background_job(job_id) do
      {:ok, bg_job} ->
        Gitclass.Jobs.fail_job(bg_job, error_message)

      {:error, _} ->
        Logger.warning("Could not find background job with ID: #{job_id}")
        :ok
    end
  end
end
