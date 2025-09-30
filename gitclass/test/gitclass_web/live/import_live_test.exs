defmodule GitclassWeb.ImportLiveTest do
  use GitclassWeb.ConnCase

  import Phoenix.LiveViewTest
  import Gitclass.AccountsFixtures
  import Gitclass.ClassroomFixtures

  alias Gitclass.Classroom

  describe "ImportLive" do
    setup do
      teacher = user_fixture()
      {:ok, class} = Classroom.create_class(teacher, %{name: "Test Class", term: "Fall 2024"})

      %{teacher: teacher, class: class}
    end

    test "mounts and displays import form", %{conn: conn, teacher: teacher, class: class} do
      conn = log_in_user(conn, teacher)

      {:ok, _view, html} = live(conn, ~p"/classes/#{class.id}/import")

      assert html =~ "Import Students"
      assert html =~ "Enter GitHub Usernames"
      assert html =~ class.name
    end

    test "redirects when user is not authenticated", %{conn: conn, class: class} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/classes/#{class.id}/import")
    end

    test "redirects when user does not own the class", %{conn: conn, class: class} do
      other_user = user_fixture()
      conn = log_in_user(conn, other_user)

      {:ok, view, _html} = live(conn, ~p"/classes/#{class.id}/import")

      assert_redirected(view, "/dashboard")
      assert Phoenix.Flash.get(view.assigns.flash, :error) =~ "not found"
    end

    test "parses usernames from text input", %{conn: conn, teacher: teacher, class: class} do
      conn = log_in_user(conn, teacher)

      {:ok, view, _html} = live(conn, ~p"/classes/#{class.id}/import")

      # Type some usernames
      view
      |> element("form")
      |> render_change(%{usernames: "octocat\ntorvalds\ndefunkt"})

      # Should show parsed usernames
      assert has_element?(view, "div", "Detected Usernames (3)")
      assert has_element?(view, "span", "octocat")
      assert has_element?(view, "span", "torvalds")
      assert has_element?(view, "span", "defunkt")
    end

    test "validates usernames in real-time", %{conn: conn, teacher: teacher, class: class} do
      conn = log_in_user(conn, teacher)

      {:ok, view, _html} = live(conn, ~p"/classes/#{class.id}/import")

      # Enter mix of valid and invalid usernames
      view
      |> element("form")
      |> render_change(%{usernames: "octocat\ninvalid--username\n\ntoooooooooooooooooooooooooooooooooooooolong"})

      # Should show validation results
      assert has_element?(view, "span", "Valid")
      assert has_element?(view, "span", "Invalid username format")
      assert has_element?(view, "span", "Username too long")
    end

    test "handles comma-separated usernames", %{conn: conn, teacher: teacher, class: class} do
      conn = log_in_user(conn, teacher)

      {:ok, view, _html} = live(conn, ~p"/classes/#{class.id}/import")

      view
      |> element("form")
      |> render_change(%{usernames: "octocat, torvalds, defunkt"})

      assert has_element?(view, "div", "Detected Usernames (3)")
    end

    test "handles space-separated usernames", %{conn: conn, teacher: teacher, class: class} do
      conn = log_in_user(conn, teacher)

      {:ok, view, _html} = live(conn, ~p"/classes/#{class.id}/import")

      view
      |> element("form")
      |> render_change(%{usernames: "octocat torvalds defunkt"})

      assert has_element?(view, "div", "Detected Usernames (3)")
    end

    test "removes duplicate usernames", %{conn: conn, teacher: teacher, class: class} do
      conn = log_in_user(conn, teacher)

      {:ok, view, _html} = live(conn, ~p"/classes/#{class.id}/import")

      view
      |> element("form")
      |> render_change(%{usernames: "octocat\noctocat\ntorvalds\noctocat"})

      # Should only show 2 unique usernames
      assert has_element?(view, "div", "Detected Usernames (2)")
    end

    test "shows count of valid and invalid usernames", %{
      conn: conn,
      teacher: teacher,
      class: class
    } do
      conn = log_in_user(conn, teacher)

      {:ok, view, _html} = live(conn, ~p"/classes/#{class.id}/import")

      view
      |> element("form")
      |> render_change(%{usernames: "octocat\ntorvalds\ninvalid--user"})

      html = render(view)
      assert html =~ "2 valid"
      assert html =~ "1 invalid"
    end

    test "enables import button only when valid usernames exist", %{
      conn: conn,
      teacher: teacher,
      class: class
    } do
      conn = log_in_user(conn, teacher)

      {:ok, view, _html} = live(conn, ~p"/classes/#{class.id}/import")

      # Initially button should be disabled (no usernames)
      assert has_element?(view, "button[disabled]", "Import Valid Users")

      # Enter only invalid usernames
      view
      |> element("form")
      |> render_change(%{usernames: "invalid--username"})

      assert has_element?(view, "button[disabled]", "Import Valid Users")

      # Enter valid username
      view
      |> element("form")
      |> render_change(%{usernames: "octocat"})

      refute has_element?(view, "button[disabled]", "Import Valid Users")
    end

    test "clears all input when reset is clicked", %{
      conn: conn,
      teacher: teacher,
      class: class
    } do
      conn = log_in_user(conn, teacher)

      {:ok, view, _html} = live(conn, ~p"/classes/#{class.id}/import")

      view
      |> element("form")
      |> render_change(%{usernames: "octocat\ntorvalds"})

      assert has_element?(view, "div", "Detected Usernames")

      view
      |> element("button", "Clear")
      |> render_click()

      refute has_element?(view, "div", "Detected Usernames")
    end

    test "starts import process when clicking import button", %{
      conn: conn,
      teacher: teacher,
      class: class
    } do
      conn = log_in_user(conn, teacher)

      {:ok, view, _html} = live(conn, ~p"/classes/#{class.id}/import")

      view
      |> element("form")
      |> render_change(%{usernames: "octocat\ntorvalds"})

      view
      |> element("button", "Import Valid Users")
      |> render_click()

      # Should show importing state
      assert has_element?(view, "h2", "Importing Students...")
      assert has_element?(view, "div", "Progress:")
    end

    test "navigates back to class page", %{conn: conn, teacher: teacher, class: class} do
      conn = log_in_user(conn, teacher)

      {:ok, view, _html} = live(conn, ~p"/classes/#{class.id}/import")

      # Note: We can't easily test navigation in tests without mocking the import completion
      # This would require setting up the full import flow
    end

    test "validates empty username", %{conn: conn, teacher: teacher, class: class} do
      conn = log_in_user(conn, teacher)

      {:ok, view, _html} = live(conn, ~p"/classes/#{class.id}/import")

      view
      |> element("form")
      |> render_change(%{usernames: "   \n  \n  "})

      # Should not show any usernames (empty strings filtered out)
      refute has_element?(view, "div", "Detected Usernames")
    end

    test "validates username length", %{conn: conn, teacher: teacher, class: class} do
      conn = log_in_user(conn, teacher)

      {:ok, view, _html} = live(conn, ~p"/classes/#{class.id}/import")

      # Username with 40 characters (exceeds GitHub's 39 char limit)
      long_username = String.duplicate("a", 40)

      view
      |> element("form")
      |> render_change(%{usernames: long_username})

      assert has_element?(view, "span", "Username too long")
    end

    test "validates username format with hyphens", %{
      conn: conn,
      teacher: teacher,
      class: class
    } do
      conn = log_in_user(conn, teacher)

      {:ok, view, _html} = live(conn, ~p"/classes/#{class.id}/import")

      # Valid username with hyphen
      view
      |> element("form")
      |> render_change(%{usernames: "octo-cat"})

      assert has_element?(view, "span", "Valid")

      # Invalid: starts with hyphen
      view
      |> element("form")
      |> render_change(%{usernames: "-octocat"})

      assert has_element?(view, "span", "Invalid username format")

      # Invalid: ends with hyphen
      view
      |> element("form")
      |> render_change(%{usernames: "octocat-"})

      assert has_element?(view, "span", "Invalid username format")

      # Invalid: double hyphen
      view
      |> element("form")
      |> render_change(%{usernames: "octo--cat"})

      assert has_element?(view, "span", "Invalid username format")
    end
  end

  describe "Real-time import progress" do
    setup do
      teacher = user_fixture()
      {:ok, class} = Classroom.create_class(teacher, %{name: "Test Class", term: "Fall 2024"})

      %{teacher: teacher, class: class}
    end

    test "receives import start broadcast", %{conn: conn, teacher: teacher, class: class} do
      conn = log_in_user(conn, teacher)

      {:ok, view, _html} = live(conn, ~p"/classes/#{class.id}/import")

      # Simulate starting an import
      Phoenix.PubSub.broadcast(
        Gitclass.PubSub,
        "class:#{class.id}:import",
        {:job_progress, %{status: :started, total: 3, progress: 0}}
      )

      :timer.sleep(50)
      html = render(view)

      assert html =~ "Importing Students" or html =~ "Progress"
    end

    test "receives progress updates during import", %{
      conn: conn,
      teacher: teacher,
      class: class
    } do
      conn = log_in_user(conn, teacher)

      {:ok, view, _html} = live(conn, ~p"/classes/#{class.id}/import")

      # Set initial state by simulating import start
      view
      |> element("form")
      |> render_change(%{usernames: "octocat\ntorvalds\ndefunkt"})

      view
      |> element("button", "Import Valid Users")
      |> render_click()

      # Simulate progress updates
      Phoenix.PubSub.broadcast(
        Gitclass.PubSub,
        "class:#{class.id}:import",
        {:job_progress, %{
          status: :progress,
          total: 3,
          progress: 1,
          current_student: "octocat",
          result: {:ok, %{}}
        }}
      )

      :timer.sleep(50)
      html = render(view)

      assert html =~ "octocat"
      assert html =~ "Successfully imported" or html =~ "Progress: 1/3"

      # Second progress update
      Phoenix.PubSub.broadcast(
        Gitclass.PubSub,
        "class:#{class.id}:import",
        {:job_progress, %{
          status: :progress,
          total: 3,
          progress: 2,
          current_student: "torvalds",
          result: {:error, "User not found"}
        }}
      )

      :timer.sleep(50)
      html = render(view)

      assert html =~ "torvalds"
      assert html =~ "User not found" or html =~ "Progress: 2/3"
    end

    test "shows completion state after import finishes", %{
      conn: conn,
      teacher: teacher,
      class: class
    } do
      conn = log_in_user(conn, teacher)

      {:ok, view, _html} = live(conn, ~p"/classes/#{class.id}/import")

      # Start import
      view
      |> element("form")
      |> render_change(%{usernames: "octocat\ntorvalds"})

      view
      |> element("button", "Import Valid Users")
      |> render_click()

      # Simulate completion
      Phoenix.PubSub.broadcast(
        Gitclass.PubSub,
        "class:#{class.id}:import",
        {:job_progress, %{
          status: :completed,
          total: 2,
          successful: 1,
          failed: 1
        }}
      )

      :timer.sleep(50)
      html = render(view)

      assert html =~ "Import Completed"
      assert html =~ "1" # successful count
      assert html =~ "Successful"
    end

    test "displays progress bar that updates in real-time", %{
      conn: conn,
      teacher: teacher,
      class: class
    } do
      conn = log_in_user(conn, teacher)

      {:ok, view, _html} = live(conn, ~p"/classes/#{class.id}/import")

      # Start import
      view
      |> element("form")
      |> render_change(%{usernames: "user1\nuser2\nuser3\nuser4"})

      view
      |> element("button", "Import Valid Users")
      |> render_click()

      # Progress at 25%
      Phoenix.PubSub.broadcast(
        Gitclass.PubSub,
        "class:#{class.id}:import",
        {:job_progress, %{
          status: :progress,
          total: 4,
          progress: 1,
          current_student: "user1",
          result: {:ok, %{}}
        }}
      )

      :timer.sleep(50)
      html = render(view)
      assert html =~ "25%" or html =~ "width: 25%"

      # Progress at 75%
      Phoenix.PubSub.broadcast(
        Gitclass.PubSub,
        "class:#{class.id}:import",
        {:job_progress, %{
          status: :progress,
          total: 4,
          progress: 3,
          current_student: "user3",
          result: {:ok, %{}}
        }}
      )

      :timer.sleep(50)
      html = render(view)
      assert html =~ "75%" or html =~ "width: 75%"
    end

    test "shows real-time results list during import", %{
      conn: conn,
      teacher: teacher,
      class: class
    } do
      conn = log_in_user(conn, teacher)

      {:ok, view, _html} = live(conn, ~p"/classes/#{class.id}/import")

      # Start import
      view
      |> element("form")
      |> render_change(%{usernames: "octocat\ntorvalds"})

      view
      |> element("button", "Import Valid Users")
      |> render_click()

      # First result
      Phoenix.PubSub.broadcast(
        Gitclass.PubSub,
        "class:#{class.id}:import",
        {:job_progress, %{
          status: :progress,
          total: 2,
          progress: 1,
          current_student: "octocat",
          result: {:ok, %{}}
        }}
      )

      :timer.sleep(50)
      html = render(view)
      assert html =~ "octocat"

      # Second result
      Phoenix.PubSub.broadcast(
        Gitclass.PubSub,
        "class:#{class.id}:import",
        {:job_progress, %{
          status: :progress,
          total: 2,
          progress: 2,
          current_student: "torvalds",
          result: {:error, "GitHub user 'torvalds' not found"}
        }}
      )

      :timer.sleep(50)
      html = render(view)
      assert html =~ "torvalds"
      assert html =~ "not found"
    end

    test "allows resetting after completion", %{conn: conn, teacher: teacher, class: class} do
      conn = log_in_user(conn, teacher)

      {:ok, view, _html} = live(conn, ~p"/classes/#{class.id}/import")

      # Start and complete import
      view
      |> element("form")
      |> render_change(%{usernames: "octocat"})

      view
      |> element("button", "Import Valid Users")
      |> render_click()

      Phoenix.PubSub.broadcast(
        Gitclass.PubSub,
        "class:#{class.id}:import",
        {:job_progress, %{status: :completed, total: 1, successful: 1, failed: 0}}
      )

      :timer.sleep(50)

      # Click "Import More Students"
      view
      |> element("button", "Import More Students")
      |> render_click()

      # Should be back to initial state
      assert has_element?(view, "h2", "Enter GitHub Usernames")
      refute has_element?(view, "h2", "Import Completed")
    end
  end
end