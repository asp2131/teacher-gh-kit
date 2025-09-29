defmodule Gitclass.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      GitclassWeb.Telemetry,
      Gitclass.Repo,
      {DNSCluster, query: Application.get_env(:gitclass, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Gitclass.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Gitclass.Finch},
      # Start the Finch HTTP client for GitHub API
      {Finch, name: GitclassFinch},
      # Start Oban background job processor
      {Oban, Application.fetch_env!(:gitclass, Oban)},
      # Start a worker by calling: Gitclass.Worker.start_link(arg)
      # {Gitclass.Worker, arg},
      # Start to serve requests, typically the last entry
      GitclassWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Gitclass.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    GitclassWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
