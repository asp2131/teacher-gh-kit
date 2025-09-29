defmodule Gitclass.Workers.RefreshCommitsWorker do
  @moduledoc """
  Background worker for refreshing commit data for all active classes.
  Runs every 2 minutes via cron job.
  """

  use Gitclass.Workers.BaseWorker,
    queue: :github_api,
    max_attempts: 2

  alias Gitclass.{Classroom, GitHub}

  def execute(%Oban.Job{args: args}) do
    class_id = Map.get(args, "class_id")

    if class_id do
      refresh_class_commits(class_id)
    else
      refresh_all_commits()
    end
  end

  defp refresh_all_commits do
    # Get all active classes (classes with students)
    active_classes = get_active_classes()

    Logger.info("Refreshing commits for #{length(active_classes)} active classes")

    results =
      active_classes
      |> Enum.map(&refresh_class_commits/1)
      |> Enum.reduce(%{successful: 0, failed: 0}, fn
        {:ok, _}, acc -> %{acc | successful: acc.successful + 1}
        {:error, _}, acc -> %{acc | failed: acc.failed + 1}
      end)

    Logger.info("Commit refresh completed: #{results.successful} successful, #{results.failed} failed")
    {:ok, results}
  end

  defp refresh_class_commits(class_id) do
    class = Classroom.get_class_with_students!(class_id)
    students = Classroom.list_class_students(class)

    if length(students) == 0 do
      {:ok, :no_students}
    else
      Logger.info("Refreshing commits for class '#{class.name}' with #{length(students)} students")

      # Process students in batches to avoid overwhelming GitHub API
      students
      |> Enum.chunk_every(5)  # Process 5 students at a time
      |> Enum.each(fn batch ->
        batch
        |> Enum.each(&refresh_student_commits(class_id, &1))

        # Small delay between batches to be nice to GitHub API
        Process.sleep(1000)
      end)

      broadcast_progress("class:#{class_id}:commits", %{
        type: :refresh_completed,
        timestamp: DateTime.utc_now(),
        student_count: length(students)
      })

      {:ok, :completed}
    end
  end

  defp refresh_student_commits(class_id, student) do
    case GitHub.fetch_recent_commits(student.student_github_username, 5) do
      {:ok, commits} ->
        # Update last commit timestamp
        last_commit_at = get_latest_commit_time(commits)

        if last_commit_at do
          Classroom.update_class_student(student, %{last_commit_at: last_commit_at})
        end

        # Update commit activity calendar
        update_commit_activities(class_id, student.student_github_username, commits)

        broadcast_progress("class:#{class_id}:students", %{
          type: :commit_update,
          username: student.student_github_username,
          last_commit_at: last_commit_at,
          commit_count: length(commits)
        })

        {:ok, length(commits)}

      {:error, :rate_limited} ->
        Logger.warning("Rate limited while fetching commits for #{student.student_github_username}")
        raise %{reason: :rate_limited}

      {:error, reason} ->
        Logger.warning("Failed to fetch commits for #{student.student_github_username}: #{reason}")
        {:error, reason}
    end
  end

  defp get_latest_commit_time(commits) when length(commits) > 0 do
    commits
    |> Enum.map(fn commit ->
      case DateTime.from_iso8601(commit.date) do
        {:ok, datetime, _} -> datetime
        _ -> nil
      end
    end)
    |> Enum.filter(& &1)
    |> Enum.max(DateTime, fn -> nil end)
  end

  defp get_latest_commit_time(_), do: nil

  defp update_commit_activities(class_id, username, commits) do
    # Group commits by date and repository
    commits_by_date_repo =
      commits
      |> Enum.group_by(fn commit ->
        case DateTime.from_iso8601(commit.date) do
          {:ok, datetime, _} ->
            {DateTime.to_date(datetime), commit.repository}
          _ ->
            nil
        end
      end)
      |> Map.delete(nil)

    # Create or update commit activity records
    commits_by_date_repo
    |> Enum.each(fn {{date, repo_name}, day_commits} ->
      last_commit_at = get_latest_commit_time(day_commits)

      attrs = %{
        class_id: class_id,
        student_username: username,
        commit_date: date,
        repository_name: repo_name,
        commit_count: length(day_commits),
        last_commit_at: last_commit_at
      }

      Classroom.upsert_commit_activity(attrs)
    end)
  end

  defp get_active_classes do
    Classroom.list_active_classes()
  end
end
