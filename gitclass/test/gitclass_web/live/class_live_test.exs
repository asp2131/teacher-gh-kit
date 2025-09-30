defmodule GitclassWeb.ClassLiveTest do
  use GitclassWeb.ConnCase

  import Phoenix.LiveViewTest
  import Gitclass.AccountsFixtures
  import Gitclass.ClassroomFixtures

  alias Gitclass.Classroom

  describe "ClassLive" do
    setup do
      teacher = user_fixture()
      {:ok, class} = Classroom.create_class(teacher, %{name: "Test Class", term: "Fall 2024"})

      %{teacher: teacher, class: class}
    end

    test "mounts and displays class information", %{conn: conn, teacher: teacher, class: class} do
      conn = log_in_user(conn, teacher)

      {:ok, _view, html} = live(conn, ~p"/classes/#{class.id}")

      assert html =~ "Test Class"
      assert html =~ "Fall 2024"
      assert html =~ "No students yet"
    end

    test "redirects when user is not authenticated", %{conn: conn, class: class} do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/classes/#{class.id}")
    end

    test "redirects when user does not own the class", %{conn: conn, class: class} do
      other_user = user_fixture()
      conn = log_in_user(conn, other_user)

      {:ok, view, _html} = live(conn, ~p"/classes/#{class.id}")

      assert_redirected(view, "/dashboard")
      assert Phoenix.Flash.get(view.assigns.flash, :error) =~ "not found"
    end

    test "displays students when they exist", %{conn: conn, teacher: teacher, class: class} do
      {:ok, _student} =
        Classroom.add_student_to_class(class, "octocat", %{
          student_name: "Octocat",
          student_avatar_url: "https://avatars.githubusercontent.com/u/583231"
        })

      conn = log_in_user(conn, teacher)

      {:ok, _view, html} = live(conn, ~p"/classes/#{class.id}")

      assert html =~ "Octocat"
      assert html =~ "@octocat"
      assert html =~ "1 student(s) in this class"
    end

    test "shows import modal when clicked", %{conn: conn, teacher: teacher, class: class} do
      conn = log_in_user(conn, teacher)

      {:ok, view, _html} = live(conn, ~p"/classes/#{class.id}")

      refute has_element?(view, "textarea[name='usernames']")

      view
      |> element("button", "Import Students")
      |> render_click()

      assert has_element?(view, "textarea[name='usernames']")
      assert has_element?(view, "h3", "Import Students")
    end

    test "hides import modal when cancel is clicked", %{
      conn: conn,
      teacher: teacher,
      class: class
    } do
      conn = log_in_user(conn, teacher)

      {:ok, view, _html} = live(conn, ~p"/classes/#{class.id}")

      view
      |> element("button", "Import Students")
      |> render_click()

      assert has_element?(view, "textarea[name='usernames']")

      view
      |> element("button", "Cancel")
      |> render_click()

      refute has_element?(view, "textarea[name='usernames']")
    end

    test "imports students with valid usernames", %{
      conn: conn,
      teacher: teacher,
      class: class
    } do
      conn = log_in_user(conn, teacher)

      {:ok, view, _html} = live(conn, ~p"/classes/#{class.id}")

      view
      |> element("button", "Import Students")
      |> render_click()

      # Note: This test would require mocking GitHub API
      # For now, we'll just verify the form submission works
      view
      |> form("form", %{usernames: "octocat\ntorvalds"})
      |> render_submit()

      # The job would be enqueued here
      assert_push_event(view, "job_progress", %{status: :started})
    end

    test "shows error when importing with no usernames", %{
      conn: conn,
      teacher: teacher,
      class: class
    } do
      conn = log_in_user(conn, teacher)

      {:ok, view, _html} = live(conn, ~p"/classes/#{class.id}")

      view
      |> element("button", "Import Students")
      |> render_click()

      view
      |> form("form", %{usernames: ""})
      |> render_submit()

      assert view
             |> element(".alert-error")
             |> render() =~ "at least one GitHub username"
    end

    test "removes a student when remove button is clicked", %{
      conn: conn,
      teacher: teacher,
      class: class
    } do
      {:ok, _student} =
        Classroom.add_student_to_class(class, "octocat", %{
          student_name: "Octocat",
          student_avatar_url: "https://avatars.githubusercontent.com/u/583231"
        })

      conn = log_in_user(conn, teacher)

      {:ok, view, html} = live(conn, ~p"/classes/#{class.id}")

      assert html =~ "Octocat"

      view
      |> element("button", "Remove")
      |> render_click()

      refute has_element?(view, "p", "Octocat")
      assert has_element?(view, "h3", "No students yet")
    end

    test "shows edit class modal when edit button is clicked", %{
      conn: conn,
      teacher: teacher,
      class: class
    } do
      conn = log_in_user(conn, teacher)

      {:ok, view, _html} = live(conn, ~p"/classes/#{class.id}")

      refute has_element?(view, "h3", "Edit Class")

      view
      |> element("button", "Edit Class")
      |> render_click()

      assert has_element?(view, "h3", "Edit Class")
      assert has_element?(view, "input[name='class[name]']")
    end

    test "updates class information", %{conn: conn, teacher: teacher, class: class} do
      conn = log_in_user(conn, teacher)

      {:ok, view, _html} = live(conn, ~p"/classes/#{class.id}")

      view
      |> element("button", "Edit Class")
      |> render_click()

      view
      |> form("form", %{class: %{name: "Updated Class Name", term: "Spring 2025"}})
      |> render_submit()

      assert has_element?(view, "h1", "Updated Class Name")
      assert has_element?(view, "p", "Spring 2025")
    end

    test "validates class form with live validation", %{
      conn: conn,
      teacher: teacher,
      class: class
    } do
      conn = log_in_user(conn, teacher)

      {:ok, view, _html} = live(conn, ~p"/classes/#{class.id}")

      view
      |> element("button", "Edit Class")
      |> render_click()

      # Try to submit with empty name
      html =
        view
        |> form("form", %{class: %{name: ""}})
        |> render_change()

      assert html =~ "can&#39;t be blank" or html =~ "can't be blank"
    end

    test "triggers commit refresh", %{conn: conn, teacher: teacher, class: class} do
      conn = log_in_user(conn, teacher)

      {:ok, view, _html} = live(conn, ~p"/classes/#{class.id}")

      view
      |> element("button", "Refresh Commits")
      |> render_click()

      # The job would be enqueued here
      assert view
             |> element(".alert-info")
             |> render() =~ "Refreshing commit data"
    end

    test "displays student with GitHub Pages repo indicator", %{
      conn: conn,
      teacher: teacher,
      class: class
    } do
      {:ok, _student} =
        Classroom.add_student_to_class(class, "octocat", %{
          student_name: "Octocat",
          student_avatar_url: "https://avatars.githubusercontent.com/u/583231",
          has_pages_repo: true,
          live_site_url: "https://octocat.github.io"
        })

      conn = log_in_user(conn, teacher)

      {:ok, _view, html} = live(conn, ~p"/classes/#{class.id}")

      assert html =~ "Pages Repo"
      assert html =~ "https://octocat.github.io"
    end

    test "displays student without GitHub Pages repo", %{
      conn: conn,
      teacher: teacher,
      class: class
    } do
      {:ok, _student} =
        Classroom.add_student_to_class(class, "octocat", %{
          student_name: "Octocat",
          student_avatar_url: "https://avatars.githubusercontent.com/u/583231",
          has_pages_repo: false
        })

      conn = log_in_user(conn, teacher)

      {:ok, _view, html} = live(conn, ~p"/classes/#{class.id}")

      assert html =~ "No Repo"
    end

    test "displays relative time for last commit", %{
      conn: conn,
      teacher: teacher,
      class: class
    } do
      one_hour_ago = DateTime.utc_now() |> DateTime.add(-3600, :second)

      {:ok, _student} =
        Classroom.add_student_to_class(class, "octocat", %{
          student_name: "Octocat",
          student_avatar_url: "https://avatars.githubusercontent.com/u/583231",
          last_commit_at: one_hour_ago
        })

      conn = log_in_user(conn, teacher)

      {:ok, _view, html} = live(conn, ~p"/classes/#{class.id}")

      assert html =~ "Last commit:"
      assert html =~ "hour" or html =~ "ago"
    end
  end

  describe "Real-time updates" do
    setup do
      teacher = user_fixture()
      {:ok, class} = Classroom.create_class(teacher, %{name: "Test Class", term: "Fall 2024"})

      {:ok, student} =
        Classroom.add_student_to_class(class, "octocat", %{
          student_name: "Octocat",
          student_avatar_url: "https://avatars.githubusercontent.com/u/583231"
        })

      %{teacher: teacher, class: class, student: student}
    end

    test "receives commit update via PubSub", %{
      conn: conn,
      teacher: teacher,
      class: class
    } do
      conn = log_in_user(conn, teacher)

      {:ok, view, _html} = live(conn, ~p"/classes/#{class.id}")

      # Simulate a commit update broadcast
      Phoenix.PubSub.broadcast(
        Gitclass.PubSub,
        "class:#{class.id}:students",
        {:job_progress, %{
          type: :commit_update,
          username: "octocat",
          last_commit_at: DateTime.utc_now(),
          commit_count: 5
        }}
      )

      # The view should update with the new commit time
      assert has_element?(view, "p", "Last commit:")
    end

    test "receives pages repo update via PubSub", %{
      conn: conn,
      teacher: teacher,
      class: class
    } do
      conn = log_in_user(conn, teacher)

      {:ok, view, html} = live(conn, ~p"/classes/#{class.id}")

      # Initially should not have pages repo
      assert html =~ "No Repo" or not (html =~ "Pages Repo")

      # Simulate a repository verification broadcast
      Phoenix.PubSub.broadcast(
        Gitclass.PubSub,
        "class:#{class.id}:students",
        {:job_progress, %{
          type: :pages_repo_update,
          username: "octocat",
          status: :verified,
          data: %{
            html_url: "https://github.com/octocat/octocat.github.io",
            pages_url: "https://octocat.github.io"
          }
        }}
      )

      # Give it a moment to process
      :timer.sleep(100)

      # The view should update with the verified status
      html = render(view)
      assert html =~ "Pages Repo" or html =~ "github.io"
    end

    test "receives import progress updates via PubSub", %{
      conn: conn,
      teacher: teacher,
      class: class
    } do
      conn = log_in_user(conn, teacher)

      {:ok, view, _html} = live(conn, ~p"/classes/#{class.id}")

      # Open import modal
      view
      |> element("button", "Import Students")
      |> render_click()

      # Simulate import start
      Phoenix.PubSub.broadcast(
        Gitclass.PubSub,
        "class:#{class.id}:import",
        {:job_progress, %{status: :started, total: 3, progress: 0}}
      )

      :timer.sleep(50)
      html = render(view)
      assert html =~ "Starting import" or html =~ "Importing students"

      # Simulate progress
      Phoenix.PubSub.broadcast(
        Gitclass.PubSub,
        "class:#{class.id}:import",
        {:job_progress, %{status: :progress, total: 3, progress: 2}}
      )

      :timer.sleep(50)
      html = render(view)
      assert html =~ "(2/3)" or html =~ "Importing"

      # Simulate completion
      Phoenix.PubSub.broadcast(
        Gitclass.PubSub,
        "class:#{class.id}:import",
        {:job_progress, %{
          status: :completed,
          total: 3,
          successful: 2,
          failed: 1
        }}
      )

      :timer.sleep(50)
      html = render(view)
      assert html =~ "Import completed" or html =~ "Successfully imported: 2"
    end

    test "receives commit refresh completed broadcast", %{
      conn: conn,
      teacher: teacher,
      class: class
    } do
      conn = log_in_user(conn, teacher)

      {:ok, view, _html} = live(conn, ~p"/classes/#{class.id}")

      # Simulate commit refresh completion
      Phoenix.PubSub.broadcast(
        Gitclass.PubSub,
        "class:#{class.id}:commits",
        {:job_progress, %{type: :refresh_completed, student_count: 1}}
      )

      :timer.sleep(50)

      # Should show success message
      assert view
             |> element(".alert-info")
             |> render() =~ "Commit data refreshed"
    end
  end
end