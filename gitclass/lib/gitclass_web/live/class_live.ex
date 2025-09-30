defmodule GitclassWeb.ClassLive do
  use GitclassWeb, :live_view

  alias Gitclass.{Classroom, Jobs}

  @impl true
  def mount(%{"id" => class_id}, _session, socket) do
    user = socket.assigns.current_user

    # Load the class and verify ownership
    case Classroom.get_class!(class_id) do
      %{teacher_id: teacher_id} = class when teacher_id == user.id ->
        # Load students for this class
        students = Classroom.list_class_students(class)

        # Subscribe to real-time updates for this class
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Gitclass.PubSub, "class:#{class_id}:students")
          Phoenix.PubSub.subscribe(Gitclass.PubSub, "class:#{class_id}:commits")
          Phoenix.PubSub.subscribe(Gitclass.PubSub, "class:#{class_id}:import")
        end

        {:ok,
         socket
         |> assign(:class, class)
         |> assign(:students, students)
         |> assign(:page_title, class.name)
         |> assign(:show_create_modal, false)
         |> assign(:show_import_modal, false)
         |> assign(:import_status, nil)
         |> assign(:form, to_form(Classroom.change_class(class)))}

      _ ->
        # Not authorized or class not found
        {:ok,
         socket
         |> put_flash(:error, "Class not found or you don't have permission to view it")
         |> redirect(to: ~p"/dashboard")}
    end
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("show_import_modal", _params, socket) do
    {:noreply, assign(socket, :show_import_modal, true)}
  end

  @impl true
  def handle_event("hide_import_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_import_modal, false)
     |> assign(:import_status, nil)}
  end

  @impl true
  def handle_event("import_students", %{"usernames" => usernames_text}, socket) do
    class = socket.assigns.class

    # Parse usernames from text (comma, newline, or space separated)
    usernames =
      usernames_text
      |> String.split(~r/[,\n\s]+/)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    case usernames do
      [] ->
        {:noreply,
         socket
         |> put_flash(:error, "Please enter at least one GitHub username")
         |> assign(:import_status, nil)}

      usernames ->
        # Enqueue the import job
        case Jobs.import_students(class.id, usernames) do
          {:ok, %{background_job: bg_job}} ->
            {:noreply,
             socket
             |> assign(:import_status, %{
               status: :started,
               total: length(usernames),
               progress: 0,
               job_id: bg_job.id
             })
             |> put_flash(:info, "Importing #{length(usernames)} students...")}

          {:error, _changeset} ->
            {:noreply,
             socket
             |> put_flash(:error, "Failed to start import job")
             |> assign(:import_status, nil)}
        end
    end
  end

  @impl true
  def handle_event("remove_student", %{"username" => username}, socket) do
    class = socket.assigns.class

    case Classroom.remove_student_from_class(class, username) do
      {1, _} ->
        students = Classroom.list_class_students(class)

        {:noreply,
         socket
         |> assign(:students, students)
         |> put_flash(:info, "Student #{username} removed")}

      _ ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to remove student")}
    end
  end

  @impl true
  def handle_event("refresh_commits", _params, socket) do
    class = socket.assigns.class

    case Jobs.schedule_commit_refresh(class.id) do
      {:ok, _job} ->
        {:noreply,
         socket
         |> put_flash(:info, "Refreshing commit data...")}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to schedule commit refresh")}
    end
  end

  @impl true
  def handle_event("edit_class", _params, socket) do
    {:noreply, assign(socket, :show_create_modal, true)}
  end

  @impl true
  def handle_event("hide_create_modal", _params, socket) do
    class = socket.assigns.class
    {:noreply,
     socket
     |> assign(:show_create_modal, false)
     |> assign(:form, to_form(Classroom.change_class(class)))}
  end

  @impl true
  def handle_event("validate_class", %{"class" => class_params}, socket) do
    class = socket.assigns.class

    changeset =
      class
      |> Classroom.change_class(class_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("save_class", %{"class" => class_params}, socket) do
    class = socket.assigns.class

    case Classroom.update_class(class, class_params) do
      {:ok, updated_class} ->
        {:noreply,
         socket
         |> assign(:class, updated_class)
         |> assign(:page_title, updated_class.name)
         |> assign(:show_create_modal, false)
         |> put_flash(:info, "Class updated successfully")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def handle_event("stop_propagation", _params, socket) do
    # This event is used to stop click propagation in the modal
    # We don't need to do anything here
    {:noreply, socket}
  end

  # Handle real-time student updates
  @impl true
  def handle_info({:job_progress, %{type: :commit_update} = update}, socket) do
    # Update the specific student's commit data
    students =
      Enum.map(socket.assigns.students, fn student ->
        if student.student_github_username == update.username do
          %{student | last_commit_at: update.last_commit_at}
        else
          student
        end
      end)

    {:noreply, assign(socket, :students, students)}
  end

  @impl true
  def handle_info({:job_progress, %{type: :pages_repo_update} = update}, socket) do
    # Update the specific student's repository verification status
    students =
      Enum.map(socket.assigns.students, fn student ->
        if student.student_github_username == update.username do
          case update.status do
            :verified ->
              %{
                student
                | has_pages_repo: true,
                  verification_status: "verified",
                  pages_repo_url: update.data.html_url,
                  live_site_url: update.data.pages_url
              }

            :missing ->
              %{
                student
                | has_pages_repo: false,
                  verification_status: "missing",
                  live_site_url: update.data.pages_url
              }

            _ ->
              student
          end
        else
          student
        end
      end)

    {:noreply, assign(socket, :students, students)}
  end

  @impl true
  def handle_info({:job_progress, %{status: :started} = progress}, socket) do
    {:noreply,
     assign(socket, :import_status, %{
       status: :running,
       total: progress.total,
       progress: 0
     })}
  end

  @impl true
  def handle_info({:job_progress, %{status: :progress} = progress}, socket) do
    import_status = socket.assigns.import_status

    if import_status do
      {:noreply,
       assign(socket, :import_status, %{
         import_status
         | progress: progress.progress,
           status: :running
       })}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:job_progress, %{status: :completed} = progress}, socket) do
    # Reload students list
    class = socket.assigns.class
    students = Classroom.list_class_students(class)

    {:noreply,
     socket
     |> assign(:students, students)
     |> assign(:import_status, %{
       status: :completed,
       total: progress.total,
       successful: progress.successful,
       failed: progress.failed
     })
     |> put_flash(
       :info,
       "Import completed: #{progress.successful} successful, #{progress.failed} failed"
     )}
  end

  @impl true
  def handle_info({:job_progress, %{type: :refresh_completed}}, socket) do
    # Reload all students after commit refresh
    class = socket.assigns.class
    students = Classroom.list_class_students(class)

    {:noreply,
     socket
     |> assign(:students, students)
     |> put_flash(:info, "Commit data refreshed")}
  end

  @impl true
  def handle_info(_msg, socket) do
    # Catch-all for other messages
    {:noreply, socket}
  end

  # Helper function to format relative time
  defp format_relative_time(datetime) do
    seconds_ago = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      seconds_ago < 60 ->
        "just now"

      seconds_ago < 3600 ->
        minutes = div(seconds_ago, 60)
        "#{minutes} minute#{if minutes > 1, do: "s", else: ""} ago"

      seconds_ago < 86400 ->
        hours = div(seconds_ago, 3600)
        "#{hours} hour#{if hours > 1, do: "s", else: ""} ago"

      seconds_ago < 604_800 ->
        days = div(seconds_ago, 86400)
        "#{days} day#{if days > 1, do: "s", else: ""} ago"

      true ->
        weeks = div(seconds_ago, 604_800)
        "#{weeks} week#{if weeks > 1, do: "s", else: ""} ago"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <!-- Navigation -->
      <nav class="bg-white shadow">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div class="flex justify-between h-16">
            <div class="flex items-center">
              <.link navigate={~p"/dashboard"} class="text-gray-500 hover:text-gray-700">
                <svg
                  class="h-6 w-6"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M10 19l-7-7m0 0l7-7m-7 7h18"
                  />
                </svg>
              </.link>
              <div class="ml-4">
                <h1 class="text-xl font-semibold text-gray-900">{@class.name}</h1>
                <p class="text-sm text-gray-500">{@class.term}</p>
              </div>
            </div>
            <div class="flex items-center space-x-4">
              <.link
                href={~p"/auth/logout"}
                method="delete"
                class="text-gray-500 hover:text-gray-700 px-3 py-2 rounded-md text-sm font-medium"
              >
                Sign out
              </.link>
            </div>
          </div>
        </div>
      </nav>
      <!-- Main content -->
      <div class="max-w-7xl mx-auto py-6 sm:px-6 lg:px-8">
        <div class="px-4 py-6 sm:px-0">
          <!-- Class header with actions -->
          <div class="mb-6 flex items-center justify-between">
            <div>
              <h2 class="text-2xl font-bold text-gray-900">Students</h2>
              <p class="mt-1 text-sm text-gray-600">
                {length(@students)} student(s) in this class
              </p>
            </div>
            <div class="flex space-x-3">
              <button
                type="button"
                phx-click="edit_class"
                class="inline-flex items-center px-4 py-2 border border-gray-300 shadow-sm text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
              >
                <svg class="-ml-1 mr-2 h-5 w-5 text-gray-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"
                  />
                </svg>
                Edit Class
              </button>
              <button
                type="button"
                phx-click="refresh_commits"
                class="inline-flex items-center px-4 py-2 border border-gray-300 shadow-sm text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
              >
                <svg class="-ml-1 mr-2 h-5 w-5 text-gray-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
                  />
                </svg>
                Refresh Commits
              </button>
              <button
                type="button"
                phx-click="show_import_modal"
                class="inline-flex items-center px-4 py-2 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
              >
                <svg class="-ml-1 mr-2 h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M12 6v6m0 0v6m0-6h6m-6 0H6"
                  />
                </svg>
                Import Students
              </button>
            </div>
          </div>
          <!-- Import progress -->
          <%= if @import_status do %>
            <div class="mb-6 bg-blue-50 border border-blue-200 rounded-lg p-4">
              <div class="flex items-center justify-between mb-2">
                <h3 class="text-sm font-medium text-blue-900">
                  <%= case @import_status.status do %>
                    <% :started -> %>
                      Starting import...
                    <% :running -> %>
                      Importing students... ({@import_status.progress}/{@import_status.total})
                    <% :completed -> %>
                      Import completed!
                  <% end %>
                </h3>
              </div>
              <%= if @import_status.status in [:started, :running] do %>
                <div class="w-full bg-blue-200 rounded-full h-2.5">
                  <div
                    class="bg-blue-600 h-2.5 rounded-full transition-all duration-300"
                    style={"width: #{(@import_status.progress / @import_status.total * 100) |> round()}%"}
                  >
                  </div>
                </div>
              <% end %>
              <%= if @import_status.status == :completed do %>
                <p class="text-sm text-blue-700">
                  Successfully imported: {@import_status.successful} | Failed: {@import_status.failed}
                </p>
              <% end %>
            </div>
          <% end %>
          <!-- Students list -->
          <%= if Enum.empty?(@students) do %>
            <div class="text-center py-12 bg-white rounded-lg shadow">
              <svg
                class="mx-auto h-12 w-12 text-gray-400"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z"
                />
              </svg>
              <h3 class="mt-2 text-sm font-medium text-gray-900">No students yet</h3>
              <p class="mt-1 text-sm text-gray-500">Get started by importing students.</p>
              <div class="mt-6">
                <button
                  type="button"
                  phx-click="show_import_modal"
                  class="inline-flex items-center px-4 py-2 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
                >
                  <svg class="-ml-1 mr-2 h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M12 6v6m0 0v6m0-6h6m-6 0H6"
                    />
                  </svg>
                  Import Students
                </button>
              </div>
            </div>
          <% else %>
            <div class="bg-white shadow overflow-hidden sm:rounded-md">
              <ul role="list" class="divide-y divide-gray-200">
                <li :for={student <- @students} class="px-6 py-4 hover:bg-gray-50">
                  <div class="flex items-center justify-between">
                    <div class="flex items-center min-w-0 flex-1">
                      <img
                        class="h-12 w-12 rounded-full"
                        src={student.student_avatar_url}
                        alt={student.student_name}
                      />
                      <div class="ml-4 flex-1">
                        <div class="flex items-center justify-between">
                          <p class="text-sm font-medium text-indigo-600 truncate">
                            {student.student_name}
                          </p>
                          <%= if student.has_pages_repo do %>
                            <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
                              <svg class="-ml-0.5 mr-1.5 h-2 w-2 text-green-400" fill="currentColor" viewBox="0 0 8 8">
                                <circle cx="4" cy="4" r="3" />
                              </svg>
                              Pages Repo
                            </span>
                          <% else %>
                            <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800">
                              No Repo
                            </span>
                          <% end %>
                        </div>
                        <div class="mt-1 flex items-center text-sm text-gray-500">
                          <p class="truncate">@{student.student_github_username}</p>
                          <%= if student.last_commit_at do %>
                            <span class="mx-2">•</span>
                            <p>
                              Last commit: <%= format_relative_time(student.last_commit_at) %>
                            </p>
                          <% end %>
                        </div>
                        <%= if student.live_site_url do %>
                          <div class="mt-1">
                            <a
                              href={student.live_site_url}
                              target="_blank"
                              class="text-xs text-indigo-600 hover:text-indigo-900"
                            >
                              {student.live_site_url} →
                            </a>
                          </div>
                        <% end %>
                      </div>
                    </div>
                    <div class="ml-4 flex-shrink-0">
                      <button
                        type="button"
                        phx-click="remove_student"
                        phx-value-username={student.student_github_username}
                        data-confirm="Are you sure you want to remove this student?"
                        class="inline-flex items-center px-3 py-2 border border-gray-300 shadow-sm text-sm leading-4 font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
                      >
                        Remove
                      </button>
                    </div>
                  </div>
                </li>
              </ul>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    <!-- Import Students Modal -->
    <%= if @show_import_modal do %>
      <div class="fixed z-10 inset-0 overflow-y-auto" phx-click="hide_import_modal">
        <div class="flex items-end justify-center min-h-screen pt-4 px-4 pb-20 text-center sm:block sm:p-0">
          <div class="fixed inset-0 bg-gray-500 bg-opacity-75 transition-opacity"></div>
          <span class="hidden sm:inline-block sm:align-middle sm:h-screen">&#8203;</span>
          <div
            class="inline-block align-bottom bg-white rounded-lg px-4 pt-5 pb-4 text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-lg sm:w-full sm:p-6"
            phx-click="stop_propagation"
          >
            <div>
              <h3 class="text-lg leading-6 font-medium text-gray-900">Import Students</h3>
              <div class="mt-2">
                <p class="text-sm text-gray-500">
                  Enter GitHub usernames (one per line, or comma/space separated)
                </p>
              </div>
              <.form for={%{}} phx-submit="import_students" class="mt-4">
                <textarea
                  name="usernames"
                  rows="10"
                  class="shadow-sm focus:ring-indigo-500 focus:border-indigo-500 block w-full sm:text-sm border-gray-300 rounded-md"
                  placeholder="octocat&#10;torvalds&#10;defunkt"
                />
                <div class="mt-5 sm:mt-6 sm:grid sm:grid-cols-2 sm:gap-3 sm:grid-flow-row-dense">
                  <button
                    type="submit"
                    class="w-full inline-flex justify-center rounded-md border border-transparent shadow-sm px-4 py-2 bg-indigo-600 text-base font-medium text-white hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 sm:col-start-2 sm:text-sm"
                  >
                    Import
                  </button>
                  <button
                    type="button"
                    phx-click="hide_import_modal"
                    class="mt-3 w-full inline-flex justify-center rounded-md border border-gray-300 shadow-sm px-4 py-2 bg-white text-base font-medium text-gray-700 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 sm:mt-0 sm:col-start-1 sm:text-sm"
                  >
                    Cancel
                  </button>
                </div>
              </.form>
            </div>
          </div>
        </div>
      </div>
    <% end %>
    <!-- Edit Class Modal -->
    <%= if @show_create_modal do %>
      <div class="fixed z-10 inset-0 overflow-y-auto" phx-click="hide_create_modal">
        <div class="flex items-end justify-center min-h-screen pt-4 px-4 pb-20 text-center sm:block sm:p-0">
          <div class="fixed inset-0 bg-gray-500 bg-opacity-75 transition-opacity"></div>
          <span class="hidden sm:inline-block sm:align-middle sm:h-screen">&#8203;</span>
          <div
            class="inline-block align-bottom bg-white rounded-lg px-4 pt-5 pb-4 text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-lg sm:w-full sm:p-6"
            phx-click="stop_propagation"
          >
            <div>
              <h3 class="text-lg leading-6 font-medium text-gray-900">Edit Class</h3>
              <div class="mt-4">
                <.form
                  for={@form}
                  phx-change="validate_class"
                  phx-submit="save_class"
                  class="space-y-4"
                >
                  <div>
                    <label for="name" class="block text-sm font-medium text-gray-700">
                      Class Name
                    </label>
                    <.input field={@form[:name]} type="text" required />
                  </div>
                  <div>
                    <label for="term" class="block text-sm font-medium text-gray-700">
                      Term (Optional)
                    </label>
                    <.input field={@form[:term]} type="text" />
                  </div>
                  <div class="mt-5 sm:mt-6 sm:grid sm:grid-cols-2 sm:gap-3 sm:grid-flow-row-dense">
                    <button
                      type="submit"
                      class="w-full inline-flex justify-center rounded-md border border-transparent shadow-sm px-4 py-2 bg-indigo-600 text-base font-medium text-white hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 sm:col-start-2 sm:text-sm"
                    >
                      Save
                    </button>
                    <button
                      type="button"
                      phx-click="hide_create_modal"
                      class="mt-3 w-full inline-flex justify-center rounded-md border border-gray-300 shadow-sm px-4 py-2 bg-white text-base font-medium text-gray-700 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 sm:mt-0 sm:col-start-1 sm:text-sm"
                    >
                      Cancel
                    </button>
                  </div>
                </.form>
              </div>
            </div>
          </div>
        </div>
      </div>
    <% end %>
    """
  end
end