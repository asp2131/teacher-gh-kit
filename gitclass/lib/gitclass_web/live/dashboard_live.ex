defmodule GitclassWeb.DashboardLive do
  use GitclassWeb, :live_view

  alias Gitclass.Classroom

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    classes = Classroom.list_classes_for_teacher(user)

    {:ok,
     socket
     |> assign(:classes, classes)
     |> assign(:page_title, "Dashboard")
     |> assign(:show_create_modal, false)
     |> assign(:form, to_form(Classroom.change_class(%Gitclass.Classroom.Class{})))}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("show_create_modal", _params, socket) do
    {:noreply, assign(socket, :show_create_modal, true)}
  end

  @impl true
  def handle_event("hide_create_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_create_modal, false)
     |> assign(:form, to_form(Classroom.change_class(%Gitclass.Classroom.Class{})))}
  end

  @impl true
  def handle_event("validate_class", %{"class" => class_params}, socket) do
    changeset =
      %Gitclass.Classroom.Class{}
      |> Classroom.change_class(class_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("create_class", %{"class" => class_params}, socket) do
    user = socket.assigns.current_user

    case Classroom.create_class(user, class_params) do
      {:ok, class} ->
        {:noreply,
         socket
         |> put_flash(:info, "Class created successfully")
         |> redirect(to: ~p"/classes/#{class.id}")}

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

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50">
      <!-- Navigation -->
      <nav class="bg-white shadow">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div class="flex justify-between h-16">
            <div class="flex items-center">
              <div class="flex-shrink-0">
                <h1 class="text-xl font-semibold text-gray-900">GitHub Classroom Manager</h1>
              </div>
            </div>
            <div class="flex items-center space-x-4">
              <div class="flex items-center space-x-2">
                <img class="h-8 w-8 rounded-full" src={@current_user.avatar_url} alt={@current_user.name} />
                <span class="text-sm font-medium text-gray-700">{@current_user.name || @current_user.github_username}</span>
              </div>
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
          <div class="mb-6">
            <h2 class="text-2xl font-bold text-gray-900">Your Classes</h2>
            <p class="mt-1 text-sm text-gray-600">
              Manage your JavaScript classes and monitor student GitHub activity in real-time.
            </p>
          </div>

          <!-- Classes grid -->
          <div class="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
            <!-- Create new class card -->
            <button
              type="button"
              phx-click="show_create_modal"
              class="bg-white overflow-hidden shadow rounded-lg border-2 border-dashed border-gray-300 hover:border-gray-400 transition-colors duration-200 cursor-pointer"
            >
              <div class="p-6">
                <div class="flex items-center justify-center h-32">
                  <div class="text-center">
                    <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
                    </svg>
                    <h3 class="mt-2 text-sm font-medium text-gray-900">Create New Class</h3>
                    <p class="mt-1 text-sm text-gray-500">Get started by creating a new class.</p>
                  </div>
                </div>
              </div>
            </button>

            <!-- Existing classes -->
            <div :for={class <- @classes} class="bg-white overflow-hidden shadow rounded-lg hover:shadow-md transition-shadow duration-200">
              <div class="p-6">
                <div class="flex items-center">
                  <div class="flex-shrink-0">
                    <div class="h-10 w-10 bg-indigo-100 rounded-full flex items-center justify-center">
                      <svg class="h-6 w-6 text-indigo-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.746 0 3.332.477 4.5 1.253v13C20.168 18.477 18.582 18 16.5 18c-1.746 0-3.332.477-4.5 1.253" />
                      </svg>
                    </div>
                  </div>
                  <div class="ml-4 flex-1">
                    <h3 class="text-lg font-medium text-gray-900">{class.name}</h3>
                    <p class="text-sm text-gray-500">{class.term}</p>
                  </div>
                </div>
                <div class="mt-4">
                  <div class="flex items-center justify-between">
                    <div class="flex items-center text-sm text-gray-500">
                      <svg class="flex-shrink-0 mr-1.5 h-4 w-4 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
                      </svg>
                      {class.student_count} {if class.student_count == 1, do: "student", else: "students"}
                    </div>
                    <.link
                      navigate={~p"/classes/#{class.id}"}
                      class="text-indigo-600 hover:text-indigo-900 text-sm font-medium"
                    >
                      View Class →
                    </.link>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- Empty state -->
          <div :if={Enum.empty?(@classes)} class="text-center py-12">
            <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.746 0 3.332.477 4.5 1.253v13C20.168 18.477 18.582 18 16.5 18c-1.746 0-3.332.477-4.5 1.253" />
            </svg>
            <h3 class="mt-2 text-sm font-medium text-gray-900">No classes yet</h3>
            <p class="mt-1 text-sm text-gray-500">Get started by creating your first class.</p>
            <div class="mt-6">
              <button
                type="button"
                phx-click="show_create_modal"
                class="inline-flex items-center px-4 py-2 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
              >
                <svg class="-ml-1 mr-2 h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
                </svg>
                Create Class
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    <!-- Create Class Modal -->
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
              <h3 class="text-lg leading-6 font-medium text-gray-900">Create New Class</h3>
              <div class="mt-4">
                <.form
                  for={@form}
                  phx-change="validate_class"
                  phx-submit="create_class"
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
                    <.input field={@form[:term]} type="text" placeholder="e.g., Fall 2024" />
                  </div>
                  <div class="mt-5 sm:mt-6 sm:grid sm:grid-cols-2 sm:gap-3 sm:grid-flow-row-dense">
                    <button
                      type="submit"
                      class="w-full inline-flex justify-center rounded-md border border-transparent shadow-sm px-4 py-2 bg-indigo-600 text-base font-medium text-white hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 sm:col-start-2 sm:text-sm"
                    >
                      Create
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