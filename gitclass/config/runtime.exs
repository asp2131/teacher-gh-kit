import Config

# Load environment variables from .env file in development
if config_env() == :dev do
  if File.exists?(".env") do
    # Read .env file and set environment variables
    File.read!(".env")
    |> String.split("\n")
    |> Enum.each(fn line ->
      line = String.trim(line)
      unless String.starts_with?(line, "#") or line == "" do
        [key, value] = String.split(line, "=", parts: 2)
        System.put_env(String.trim(key), String.trim(value))
      end
    end)
  end
end

# Configure GitHub OAuth with runtime environment variables
if config_env() in [:dev, :prod] do
  github_client_id = System.get_env("GITHUB_CLIENT_ID")
  github_client_secret = System.get_env("GITHUB_CLIENT_SECRET")

  if github_client_id && github_client_secret do
    config :ueberauth, Ueberauth.Strategy.Github.OAuth,
      client_id: github_client_id,
      client_secret: github_client_secret
  else
    IO.warn("GitHub OAuth credentials not found in environment variables")
  end
end

# Production runtime configuration
if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :gitclass, Gitclass.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :gitclass, GitclassWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base,
    server: true

  # GitHub API Configuration
  config :gitclass,
    github_token: System.get_env("GITHUB_TOKEN")
end
