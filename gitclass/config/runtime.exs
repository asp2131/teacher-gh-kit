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
