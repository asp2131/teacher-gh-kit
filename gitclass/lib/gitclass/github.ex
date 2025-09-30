defmodule Gitclass.GitHub do
  @moduledoc """
  Enhanced GitHub API client with rate limiting, retry logic, and comprehensive error handling.
  """

  @behaviour Gitclass.GitHubBehaviour

  require Logger

  @github_api_base "https://api.github.com"
  @user_agent "GitclassApp/1.0"

  # Rate limiting configuration
  @max_retries 3
  @base_retry_delay 1000  # 1 second
  @rate_limit_retry_delay 60_000  # 1 minute

  # Request timeout configuration
  @request_timeout 30_000  # 30 seconds

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

        {:ok, %{status: 401}} ->
          {:error, :unauthorized}

        {:ok, %{status: 403}} ->
          {:error, :rate_limited}

        {:ok, %{status: 404}} ->
          {:error, :user_not_found}

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

        {:ok, %{status: 401}} ->
          {:error, :unauthorized}

        {:ok, %{status: 403}} ->
          {:error, :rate_limited}

        {:ok, %{status: 404}} ->
          {:ok, %{exists: false, pages_url: "https://#{username}.github.io"}}

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

  defp make_request(url, headers \\ [], method \\ :get, body \\ nil, retry_count \\ 0) do
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

    request = Finch.build(method, url, all_headers, body)

    case Finch.request(request, GitclassFinch, receive_timeout: @request_timeout) do
      {:ok, %{status: status} = response} when status in [200, 201, 204] ->
        # Success response
        log_api_usage(response)
        {:ok, response}

      {:ok, %{status: 401} = response} ->
        # Authentication error - don't retry
        {:ok, response}

      {:ok, %{status: 403, headers: headers} = response} ->
        # Check if it's a rate limit error
        case get_rate_limit_info(headers) do
          {:rate_limited, reset_time} ->
            handle_rate_limit(url, headers, method, body, retry_count, reset_time)
          _ ->
            {:ok, response}  # Other 403 error (permissions, etc.)
        end

      {:ok, %{status: status} = response} when status in [404, 422] ->
        # Client errors that shouldn't be retried
        {:ok, response}

      {:ok, %{status: status}} when status >= 500 ->
        # Server errors - retry with exponential backoff
        handle_server_error(url, headers, method, body, retry_count, status)

      {:ok, response} ->
        # Other status codes
        {:ok, response}

      {:error, %{reason: :timeout}} ->
        # Timeout error - retry with exponential backoff
        handle_timeout_error(url, headers, method, body, retry_count)

      {:error, reason} ->
        # Network errors - retry with exponential backoff
        handle_network_error(url, headers, method, body, retry_count, reason)
    end
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

  # Rate limiting and error handling functions

  defp get_rate_limit_info(headers) do
    rate_limit_remaining = get_header_value(headers, "x-ratelimit-remaining")
    rate_limit_reset = get_header_value(headers, "x-ratelimit-reset")

    case {rate_limit_remaining, rate_limit_reset} do
      {"0", reset_time_str} when is_binary(reset_time_str) ->
        case Integer.parse(reset_time_str) do
          {reset_time, _} -> {:rate_limited, reset_time}
          _ -> :not_rate_limited
        end
      _ ->
        :not_rate_limited
    end
  end

  defp get_header_value(headers, key) do
    headers
    |> Enum.find(fn {k, _v} -> String.downcase(k) == String.downcase(key) end)
    |> case do
      {_k, v} -> v
      nil -> nil
    end
  end

  defp handle_rate_limit(url, headers, method, body, retry_count, reset_time) do
    current_time = System.system_time(:second)
    wait_time = max(reset_time - current_time, 0) * 1000 + 1000  # Add 1 second buffer

    Logger.warning("GitHub API rate limit exceeded. Waiting #{wait_time}ms before retry.")

    if retry_count < @max_retries do
      Process.sleep(min(wait_time, @rate_limit_retry_delay))
      make_request(url, headers, method, body, retry_count + 1)
    else
      Logger.error("Max retries exceeded for rate limited request to #{url}")
      {:error, :rate_limit_exceeded}
    end
  end

  defp handle_server_error(url, headers, method, body, retry_count, status) do
    if retry_count < @max_retries do
      delay = calculate_exponential_backoff(retry_count)
      Logger.warning("GitHub API server error (#{status}). Retrying in #{delay}ms. Attempt #{retry_count + 1}/#{@max_retries}")

      Process.sleep(delay)
      make_request(url, headers, method, body, retry_count + 1)
    else
      Logger.error("Max retries exceeded for server error #{status} on #{url}")
      {:error, :server_error}
    end
  end

  defp handle_timeout_error(url, headers, method, body, retry_count) do
    if retry_count < @max_retries do
      delay = calculate_exponential_backoff(retry_count)
      Logger.warning("GitHub API request timeout. Retrying in #{delay}ms. Attempt #{retry_count + 1}/#{@max_retries}")

      Process.sleep(delay)
      make_request(url, headers, method, body, retry_count + 1)
    else
      Logger.error("Max retries exceeded for timeout on #{url}")
      {:error, :timeout}
    end
  end

  defp handle_network_error(url, headers, method, body, retry_count, reason) do
    if retry_count < @max_retries and retryable_error?(reason) do
      delay = calculate_exponential_backoff(retry_count)
      Logger.warning("GitHub API network error: #{inspect(reason)}. Retrying in #{delay}ms. Attempt #{retry_count + 1}/#{@max_retries}")

      Process.sleep(delay)
      make_request(url, headers, method, body, retry_count + 1)
    else
      Logger.error("Network error on #{url}: #{inspect(reason)}")
      {:error, :network_error}
    end
  end

  defp calculate_exponential_backoff(retry_count) do
    # Exponential backoff with jitter: base_delay * 2^retry_count + random(0, 1000)
    base_delay = @base_retry_delay * :math.pow(2, retry_count)
    jitter = :rand.uniform(1000)
    round(base_delay + jitter)
  end

  defp retryable_error?(reason) do
    case reason do
      :econnrefused -> true
      :timeout -> true
      :nxdomain -> false  # DNS resolution failed - don't retry
      :closed -> true
      _ -> false
    end
  end

  defp log_api_usage(response) do
    headers = response.headers

    rate_limit_remaining = get_header_value(headers, "x-ratelimit-remaining")
    rate_limit_limit = get_header_value(headers, "x-ratelimit-limit")
    rate_limit_reset = get_header_value(headers, "x-ratelimit-reset")

    if rate_limit_remaining && rate_limit_limit do
      remaining = String.to_integer(rate_limit_remaining)
      limit = String.to_integer(rate_limit_limit)

      if remaining < limit * 0.1 do  # Warn when less than 10% remaining
        reset_time = if rate_limit_reset do
          case Integer.parse(rate_limit_reset) do
            {reset_timestamp, _} ->
              reset_datetime = DateTime.from_unix!(reset_timestamp)
              DateTime.to_string(reset_datetime)
            _ -> "unknown"
          end
        else
          "unknown"
        end

        Logger.warning("GitHub API rate limit low: #{remaining}/#{limit} remaining. Resets at #{reset_time}")
      end
    end
  end

  @doc """
  Gets current GitHub API rate limit status.
  """
  def get_rate_limit_status do
    url = "#{@github_api_base}/rate_limit"

    case make_request(url) do
      {:ok, %{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} ->
            core_limit = data["resources"]["core"]
            {:ok, %{
              limit: core_limit["limit"],
              remaining: core_limit["remaining"],
              reset: DateTime.from_unix!(core_limit["reset"]),
              used: core_limit["used"]
            }}
          {:error, _} ->
            {:error, :invalid_response}
        end

      {:ok, %{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %{status: 403}} ->
        {:error, :rate_limited}

      {:ok, %{status: status}} ->
        Logger.error("GitHub API returned unexpected status #{status} for rate limit")
        {:error, :api_error}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Makes a POST request to GitHub API.
  """
  def post_request(url, body, headers \\ []) do
    json_headers = [{"Content-Type", "application/json"} | headers]
    json_body = if is_map(body) or is_list(body), do: Jason.encode!(body), else: body

    make_request(url, json_headers, :post, json_body)
  end

  @doc """
  Makes a PUT request to GitHub API.
  """
  def put_request(url, body, headers \\ []) do
    json_headers = [{"Content-Type", "application/json"} | headers]
    json_body = if is_map(body) or is_list(body), do: Jason.encode!(body), else: body

    make_request(url, json_headers, :put, json_body)
  end

  @doc """
  Makes a DELETE request to GitHub API.
  """
  def delete_request(url, headers \\ []) do
    make_request(url, headers, :delete)
  end
end
