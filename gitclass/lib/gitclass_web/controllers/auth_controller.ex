defmodule GitclassWeb.AuthController do
  use GitclassWeb, :controller
  plug Ueberauth

  alias Gitclass.Accounts
  alias GitclassWeb.UserAuth

  def request(conn, _params) do
    # This will redirect to GitHub OAuth
    redirect(conn, external: Ueberauth.Strategy.Helpers.request_url(conn, :github))
  end

  def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, _params) do
    conn
    |> put_flash(:error, "Failed to authenticate with GitHub.")
    |> redirect(to: ~p"/")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    case find_or_create_user(auth) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Successfully authenticated.")
        |> UserAuth.log_in_user(user)

      {:error, reason} ->
        conn
        |> put_flash(:error, "Authentication failed: #{reason}")
        |> redirect(to: ~p"/")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end

  defp find_or_create_user(auth) do
    github_user = %{
      id: auth.uid,
      login: auth.info.nickname,
      name: auth.info.name,
      email: auth.info.email,
      avatar_url: auth.info.image
    }

    case Accounts.create_or_update_user_from_github(github_user) do
      {:ok, user} -> {:ok, user}
      {:error, %Ecto.Changeset{} = changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
        {:error, "User creation failed: #{inspect(errors)}"}
    end
  end
end