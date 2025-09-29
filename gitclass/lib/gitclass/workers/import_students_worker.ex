defmodule Gitclass.Workers.ImportStudentsWorker do
  @moduledoc """
  Background worker for importing students and fetching their GitHub data.
  """

  use Gitclass.Workers.BaseWorker,
    queue: :import,
    max_attempts: 3

  alias Gitclass.{Classroom, GitHub}

  def execute(%Oban.Job{args: %{"class_id" => class_id, "usernames" => usernames, "job_id" => job_id}}) do
    start_background_job(job_id)

    class = Classroom.get_class!(class_id)
    total_students = length(usernames)

    broadcast_progress("class:#{class_id}:import", %{
      status: :started,
      total: total_students,
      progress: 0
    })

    results =
      usernames
      |> Enum.with_index(1)
      |> Enum.map(fn {username, index} ->
        result = import_student(class, username)

        # Update progress
        update_job_progress(job_id, index, total_students)

        broadcast_progress("class:#{class_id}:import", %{
          status: :progress,
          total: total_students,
          progress: index,
          current_student: username,
          result: result
        })

        result
      end)

    # Summarize results
    successful = Enum.count(results, fn {status, _} -> status == :ok end)
    failed = total_students - successful

    complete_background_job(job_id)

    broadcast_progress("class:#{class_id}:import", %{
      status: :completed,
      total: total_students,
      successful: successful,
      failed: failed,
      results: results
    })

    {:ok, %{successful: successful, failed: failed, results: results}}
  end

  defp import_student(class, username) do
    case GitHub.fetch_user_profile(username) do
      {:ok, user_data} ->
        # Add student to class with GitHub data
        student_attrs = %{
          student_name: user_data.name || user_data.login,
          student_avatar_url: user_data.avatar_url
        }

        case Classroom.add_student_to_class(class, username, student_attrs) do
          {:ok, student} ->
            # Check for GitHub Pages repository in background
            check_pages_repository_async(class.id, username)
            {:ok, student}

          {:error, changeset} ->
            {:error, "Failed to add student: #{inspect(changeset.errors)}"}
        end

      {:error, :user_not_found} ->
        {:error, "GitHub user '#{username}' not found"}

      {:error, :invalid_username} ->
        {:error, "Invalid GitHub username format: '#{username}'"}

      {:error, reason} ->
        {:error, "GitHub API error: #{reason}"}
    end
  end

  defp check_pages_repository_async(class_id, username) do
    %{class_id: class_id, username: username}
    |> Gitclass.Workers.VerifyPagesRepoWorker.new(queue: :github_api)
    |> Oban.insert()
  end
end
