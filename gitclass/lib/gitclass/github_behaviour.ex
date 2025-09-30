defmodule Gitclass.GitHubBehaviour do
  @moduledoc """
  Behaviour for GitHub API client operations.
  This allows for mocking during tests.
  """

  @callback fetch_user_profile(username :: String.t()) ::
              {:ok, map()} | {:error, atom()}

  @callback check_pages_repository(username :: String.t()) ::
              {:ok, map()} | {:error, atom()}

  @callback fetch_latest_commit_time(username :: String.t()) ::
              {:ok, DateTime.t() | nil} | {:error, atom()}

  @callback fetch_recent_commits(username :: String.t(), days_back :: integer()) ::
              {:ok, list(map())} | {:error, atom()}

  @callback get_commit_calendar(username :: String.t(), date_range :: Range.t()) ::
              {:ok, list(map())} | {:error, atom()}

  @callback valid_username?(username :: String.t()) :: boolean()

  @callback get_rate_limit_status() ::
              {:ok, map()} | {:error, atom()}

  @callback post_request(url :: String.t(), body :: any(), headers :: list()) ::
              {:ok, map()} | {:error, atom()}

  @callback put_request(url :: String.t(), body :: any(), headers :: list()) ::
              {:ok, map()} | {:error, atom()}

  @callback delete_request(url :: String.t(), headers :: list()) ::
              {:ok, map()} | {:error, atom()}
end