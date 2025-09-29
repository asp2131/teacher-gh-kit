defmodule Gitclass.GitHub do
  @moduledoc """
  The GitHub context for interacting with the GitHub API.
  """

  require Logger

  @github_api_base "https://api.github.com"
  @user_agent "GitclassApp/1.0"

  @doc """
  Fetches a GitHub user's profile information.
  """
  def fetch_user_profile(username) when is_binary(username) do
    if not valid_username?(username) do
      {:error, :invalid_username}
    else
      url = "#{@github_api_base}/users/#{username}"
      
      case make_request(url) do
        {:ok, %{status: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, user_data} ->
              {:ok, %{
                id: user_data["id"],
                login: user_data["login"],
                name: user_data["name"],
                avatar_url: user_data["avatar_url"],
                email: user_data["email"],
                public_repos: user_data["public_repos"],
                followers: user_data["followers"],
                following: user_data["following"],
                created_at: user_data["created_at"]
              }}
            {:error, _} = error ->
              Logger.error("Failed to parse GitHub user response for #{username}: #{inspect(error)}")
              {:error, :invalid_response}
          end
        
        {:ok, %{status: 404}} ->
          {:error, :user_not_found}
        
        {:ok, %{status: 403}} ->
          {:error, :rate_limited}
        
        {:ok, %{status: status}} ->
          Logger.error("GitHub API returned unexpected status #{status} for user #{username}")
          {:error, :api_error}
        
        {:error, reason} ->
          Logger.error("Failed to fetch GitHub user #{username}: #{inspect(reason)}")
          {:error, :network_error}
      end
    end
  end

  @doc """
  Checks if a GitHub Pages repository exists for a user.
  """
  def check_pages_repository(username) when is_binary(username) do
    if not valid_username?(username) do
      {:error, :invalid_username}
    else
      repo_name = "#{username}.github.io"
      url = "#{@github_api_base}/repos/#{username}/#{repo_name}"
      
      case make_request(url) do
        {:ok, %{status: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, repo_data} ->
              {:ok, %{
                exists: true,
                name: repo_data["name"],
                full_name: repo_data["full_name"],
                html_url: repo_data["html_url"],
                clone_url: repo_data["clone_url"],
                pages_url: "https://#{username}.github.io",
                private: repo_data["private"],
                created_at: repo_data["created_at"],
                updated_at: repo_data["updated_at"],
                pushed_at: repo_data["pushed_at"]
              }}
            {:error, _} = error ->
              Logger.error("Failed to parse GitHub repo response for #{repo_name}: #{inspect(error)}")
              {:error, :invalid_response}
          end
        
        {:ok, %{status: 404}} ->
          {:ok, %{exists: false, pages_url: "https://#{username}.github.io"}}
        
        {:ok, %{status: 403}} ->
          {:error, :rate_limited}
        
        {:ok, %{status: status}} ->
          Logger.error("GitHub API returned unexpected status #{status} for repo #{repo_name}")
          {:error, :api_error}
        
        {:error, reason} ->
          Logger.error("Failed to check GitHub Pages repo #{repo_name}: #{inspect(reason)}")
          {:error, :network_error}
      end
    end
  end

  @doc """
  Fetches recent commit activity for a user's repositories.
  """
  def fetch_recent_commits(username, days_back \\ 5) when is_binary(username) and is_integer(days_back) do
    cond do
      not valid_username?(username) ->
        {:error, :invalid_username}
      
      days_back <= 0 ->
        {:error, :invalid_days}
      
      true ->
        # Get user's repositories first
        case fetch_user_repositories(username) do
          {:ok, repos} ->
            # Filter to only public repos and limit to recent activity
            active_repos = Enum.filter(repos, fn repo ->
              repo["pushed_at"] && 
              days_since_push(repo["pushed_at"]) <= days_back
            end)
            
            # Fetch commits for each active repository
            fetch_commits_for_repos(username, active_repos, days_back)
          
          {:error, _} = error ->
            error
        end
    end
  end

  @doc """
  Generates a 5-day commit calendar for a user.
  """
  def get_commit_calendar(username, date_range) when is_binary(username) do
    if not valid_username?(username) do
      {:error, :invalid_username}
    else
      case fetch_recent_commits(username, 5) do
        {:ok, commits} ->
          calendar = generate_calendar_from_commits(commits, date_range)
          {:ok, calendar}
        
        {:error, _} = error ->
          error
      end
    end
  end

  @doc """
  Validates if a GitHub username is valid format.
  """
  def valid_username?(username) when is_binary(username) do
    # GitHub username rules:
    # - May only contain alphanumeric characters or single hyphens
    # - Cannot begin or end with a hyphen
    # - Maximum 39 characters
    Regex.match?(~r/^[a-zA-Z0-9]([a-zA-Z0-9]|-(?=[a-zA-Z0-9])){0,38}$/, username)
  end

  def valid_username?(_), do: false

  # Private functions

  defp make_request(url, headers \\ []) do
    default_headers = [
      {"User-Agent", @user_agent},
      {"Accept", "application/vnd.github.v3+json"}
    ]
    
    # Add GitHub token if available
    auth_headers = case get_github_token() do
      nil -> []
      token -> [{"Authorization", "token #{token}"}]
    end
    
    all_headers = default_headers ++ auth_headers ++ headers
    
    Finch.build(:get, url, all_headers)
    |> Finch.request(GitclassFinch)
  end

  defp get_github_token do
    Application.get_env(:gitclass, :github_token) ||
    System.get_env("GITHUB_TOKEN")
  end

  defp fetch_user_repositories(username) do
    url = "#{@github_api_base}/users/#{username}/repos?type=owner&sort=pushed&per_page=30"
    
    case make_request(url) do
      {:ok, %{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, repos} when is_list(repos) ->
            {:ok, repos}
          {:error, _} = error ->
            Logger.error("Failed to parse repositories response for #{username}: #{inspect(error)}")
            {:error, :invalid_response}
        end
      
      {:ok, %{status: 404}} ->
        {:error, :user_not_found}
      
      {:ok, %{status: 403}} ->
        {:error, :rate_limited}
      
      {:error, reason} ->
        Logger.error("Failed to fetch repositories for #{username}: #{inspect(reason)}")
        {:error, :network_error}
    end
  end

  defp fetch_commits_for_repos(username, repos, days_back) do
    since_date = Date.utc_today() |> Date.add(-days_back) |> Date.to_iso8601()
    
    commits = 
      repos
      |> Enum.map(fn repo ->
        fetch_repo_commits(username, repo["name"], since_date)
      end)
      |> Enum.filter(fn
        {:ok, _} -> true
        _ -> false
      end)
      |> Enum.map(fn {:ok, commits} -> commits end)
      |> List.flatten()
    
    {:ok, commits}
  end

  defp fetch_repo_commits(username, repo_name, since_date) do
    url = "#{@github_api_base}/repos/#{username}/#{repo_name}/commits?since=#{since_date}&author=#{username}&per_page=100"
    
    case make_request(url) do
      {:ok, %{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, commits} when is_list(commits) ->
            parsed_commits = Enum.map(commits, fn commit ->
              %{
                sha: commit["sha"],
                message: commit["commit"]["message"],
                author: commit["commit"]["author"]["name"],
                date: commit["commit"]["author"]["date"],
                repository: repo_name,
                html_url: commit["html_url"]
              }
            end)
            {:ok, parsed_commits}
          
          {:error, _} ->
            {:error, :invalid_response}
        end
      
      {:ok, %{status: 404}} ->
        # Repository might be empty or not accessible
        {:ok, []}
      
      {:ok, %{status: 403}} ->
        {:error, :rate_limited}
      
      {:error, _} ->
        {:error, :network_error}
    end
  end

  defp days_since_push(pushed_at_string) do
    case DateTime.from_iso8601(pushed_at_string) do
      {:ok, pushed_at, _} ->
        now = DateTime.utc_now()
        DateTime.diff(now, pushed_at, :day)
      
      _ ->
        999  # Return large number if can't parse date
    end
  end

  defp generate_calendar_from_commits(commits, date_range) do
    # Group commits by date
    commits_by_date = 
      commits
      |> Enum.group_by(fn commit ->
        case DateTime.from_iso8601(commit.date) do
          {:ok, datetime, _} ->
            DateTime.to_date(datetime)
          _ ->
            nil
        end
      end)
      |> Map.delete(nil)
    
    # Generate calendar for date range
    date_range
    |> Enum.map(fn date ->
      commit_count = 
        commits_by_date
        |> Map.get(date, [])
        |> length()
      
      %{
        date: date,
        commit_count: commit_count,
        has_commits: commit_count > 0
      }
    end)
  end
end