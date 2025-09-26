defmodule GitclassWeb.AuthControllerTest do
  use GitclassWeb.ConnCase

  describe "GitHub OAuth" do
    test "redirects to GitHub OAuth", %{conn: conn} do
      conn = get(conn, ~p"/auth/github")
      assert redirected_to(conn, 302)
    end

    test "handles OAuth callback failure", %{conn: conn} do
      conn = 
        conn
        |> assign(:ueberauth_failure, %{})
        |> get(~p"/auth/github/callback")
      
      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Failed to authenticate"
    end
  end

  describe "logout" do
    test "logs out user", %{conn: conn} do
      conn = delete(conn, ~p"/auth/logout")
      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end
  end
end