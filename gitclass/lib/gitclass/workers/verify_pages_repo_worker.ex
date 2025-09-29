defmodule Gitclass.Workers.VerifyPagesRepoWorker do
  @moduledoc """
  Background worker for verifying GitHub Pages repositories.
  """

  use Gitclass.Workers.BaseWorker,
    queue: :github_api,
    max_attempts: 3

  alias Gitclass.{Classroom, GitHub}

  def execute(%Oban.Job{args: %{"class_id" => class_id, "username" => username}}) do
    case GitHub.check_pages_repository(username) do
      {:ok, %{exists: true} = repo_data} ->
        update_student_pages_repo(class_id, username, repo_data)
        broadcast_repo_update(class_id, username, :verified, repo_data)
        {:ok, :verified}

      {:ok, %{exists: false} = repo_data} ->
        update_student_pages_repo(class_id, username, repo_data)
        broadcast_repo_update(class_id, username, :missing, repo_data)
        {:ok, :missing}

      {:error, :rate_limited} ->
        # This will be handled by the base worker's retry logic
        raise %{reason: :rate_limited}

      {:error, reason} ->
        broadcast_repo_update(class_id, username, :error, %{error: reason})
        {:error, reason}
    end
  end

  defp update_student_pages_repo(class_id, username, repo_data) do
    case Classroom.get_class_student(class_id, username) do
      nil ->
        Logger.warning("Student #{username} not found in class #{class_id}")
        :ok

      student ->
        attrs = %{
          has_pages_repo: repo_data.exists,
          pages_repo_url: if(repo_data.exists, do: repo_data.html_url),
          live_site_url: repo_data.pages_url,
          verification_status: if(repo_data.exists, do: "verified", else: "missing")
        }

        case Classroom.update_class_student(student, attrs) do
          {:ok, _updated_student} -> :ok
          {:error, changeset} ->
            Logger.error("Failed to update student pages repo: #{inspect(changeset.errors)}")
            :error
        end
    end
  end

  defp broadcast_repo_update(class_id, username, status, data) do
    broadcast_progress("class:#{class_id}:students", %{
      type: :pages_repo_update,
      username: username,
      status: status,
      data: data
    })
  end
end
