defmodule GitclassWeb.ImportLive do
  use GitclassWeb, :live_view

  alias Gitclass.{Classroom, Jobs, GitHub}

  @impl true
  def mount(%{"class_id" => class_id}, _session, socket) do
    user = socket.assigns.current_user

    # Load the class and verify ownership
    case Classroom.get_class!(class_id) do
      %{teacher_id: teacher_id} = class when teacher_id == user.id ->
        # Subscribe to import progress updates
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Gitclass.PubSub, "class:#{class_id}:import")
        end

        {:ok,
         socket
         |> assign(:class, class)
         |> assign(:page_title, "Import Students - #{class.name}")
         |> assign(:usernames_text, "")
         |> assign(:parsed_usernames, [])
         |> assign(:validation_results, %{})
         |> assign(:import_state, :idle)
         |> assign(:import_progress, nil)
         |> assign(:import_results, nil)}

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
  def handle_event("parse_usernames", %{"usernames" => text}, socket) do
    # Parse usernames from text input
    usernames = parse_usernames(text)

    # Validate each username
    validation_results =
      usernames
      |> Enum.map(fn username ->
        {username, validate_username(username)}
      end)
      |> Enum.into(%{})

    {:noreply,
     socket
     |> assign(:usernames_text, text)
     |> assign(:parsed_usernames, usernames)
     |> assign(:validation_results, validation_results)}
  end

  @impl true
  def handle_event("start_import", _params, socket) do
    class = socket.assigns.class
    usernames = socket.assigns.parsed_usernames

    # Filter to only valid usernames
    valid_usernames =
      usernames
      |> Enum.filter(fn username ->
        case socket.assigns.validation_results[username] do
          %{valid: true} -> true
          _ -> false
        end
      end)

    case valid_usernames do
      [] ->
        {:noreply,
         socket
         |> put_flash(:error, "No valid usernames to import")}

      usernames ->
        # Enqueue the import job
        case Jobs.import_students(class.id, usernames) do
          {:ok, %{background_job: bg_job}} ->
            {:noreply,
             socket
             |> assign(:import_state, :importing)
             |> assign(:import_progress, %{
               status: :started,
               total: length(usernames),
               progress: 0,
               job_id: bg_job.id,
               results: []
             })}

          {:error, _changeset} ->
            {:noreply,
             socket
             |> put_flash(:error, "Failed to start import job")}
        end
    end
  end

  @impl true
  def handle_event("reset", _params, socket) do
    {:noreply,
     socket
     |> assign(:usernames_text, "")
     |> assign(:parsed_usernames, [])
     |> assign(:validation_results, %{})
     |> assign(:import_state, :idle)
     |> assign(:import_progress, nil)
     |> assign(:import_results, nil)}
  end

  @impl true
  def handle_event("back_to_class", _params, socket) do
    class = socket.assigns.class
    {:noreply, push_navigate(socket, to: ~p"/classes/#{class.id}")}
  end

  # Handle import progress updates
  @impl true
  def handle_info({:job_progress, %{status: :started} = progress}, socket) do
    {:noreply,
     socket
     |> assign(:import_state, :importing)
     |> update(:import_progress, fn current ->
       Map.merge(current || %{}, %{
         status: :running,
         total: progress.total,
         progress: 0,
         results: []
       })
     end)}
  end

  @impl true
  def handle_info({:job_progress, %{status: :progress} = progress}, socket) do
    import_progress = socket.assigns.import_progress

    if import_progress do
      # Add the current result to the results list
      result = %{
        username: progress.current_student,
        status: elem(progress.result, 0),
        message: format_import_result(progress.result)
      }

      updated_progress =
        import_progress
        |> Map.put(:progress, progress.progress)
        |> Map.update(:results, [result], fn results -> results ++ [result] end)

      {:noreply, assign(socket, :import_progress, updated_progress)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:job_progress, %{status: :completed} = progress}, socket) do
    {:noreply,
     socket
     |> assign(:import_state, :completed)
     |> assign(:import_results, %{
       total: progress.total,
       successful: progress.successful,
       failed: progress.failed
     })
     |> put_flash(:info, "Import completed: #{progress.successful} successful, #{progress.failed} failed")}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # Helper functions

  defp parse_usernames(text) do
    text
    |> String.split(~r/[,\n\s]+/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp validate_username(username) do
    cond do
      String.length(username) == 0 ->
        %{valid: false, error: "Username cannot be empty"}

      String.length(username) > 39 ->
        %{valid: false, error: "Username too long (max 39 characters)"}

      not GitHub.valid_username?(username) ->
        %{valid: false, error: "Invalid username format"}

      true ->
        %{valid: true}
    end
  end

  defp format_import_result({:ok, _student}) do
    "Successfully imported"
  end

  defp format_import_result({:error, message}) when is_binary(message) do
    message
  end

  defp format_import_result({:error, _}) do
    "Failed to import"
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
              <.link navigate={~p"/classes/#{@class.id}"} class="text-gray-500 hover:text-gray-700">
                <svg class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M10 19l-7-7m0 0l7-7m-7 7h18"
                  />
                </svg>
              </.link>
              <div class="ml-4">
                <h1 class="text-xl font-semibold text-gray-900">Import Students</h1>
                <p class="text-sm text-gray-500">{@class.name}</p>
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
      <div class="max-w-4xl mx-auto py-6 sm:px-6 lg:px-8">
        <div class="px-4 py-6 sm:px-0">
          <%= if @import_state == :idle do %>
            <!-- Step 1: Input usernames -->
            <div class="bg-white shadow rounded-lg p-6">
              <h2 class="text-lg font-medium text-gray-900 mb-4">Enter GitHub Usernames</h2>
              <p class="text-sm text-gray-600 mb-4">
                Enter GitHub usernames (one per line, or comma/space separated)
              </p>

              <form phx-change="parse_usernames">
                <textarea
                  name="usernames"
                  rows="10"
                  phx-debounce="300"
                  class="shadow-sm focus:ring-indigo-500 focus:border-indigo-500 block w-full sm:text-sm border-gray-300 rounded-md font-mono"
                  placeholder="octocat&#10;torvalds&#10;defunkt"
                >{@usernames_text}</textarea>
              </form>
              <!-- Username preview and validation -->
              <%= if not Enum.empty?(@parsed_usernames) do %>
                <div class="mt-6">
                  <h3 class="text-sm font-medium text-gray-900 mb-3">
                    Detected Usernames ({length(@parsed_usernames)})
                  </h3>

                  <div class="space-y-2 max-h-64 overflow-y-auto">
                    <div
                      :for={username <- @parsed_usernames}
                      class="flex items-center justify-between p-3 bg-gray-50 rounded-md"
                    >
                      <div class="flex items-center space-x-3">
                        <%= case @validation_results[username] do %>
                          <% %{valid: true} -> %>
                            <svg class="h-5 w-5 text-green-500" fill="currentColor" viewBox="0 0 20 20">
                              <path
                                fill-rule="evenodd"
                                d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"
                                clip-rule="evenodd"
                              />
                            </svg>
                            <span class="text-sm font-medium text-gray-900">{username}</span>
                            <span class="text-xs text-green-600">Valid</span>
                          <% %{valid: false, error: error} -> %>
                            <svg class="h-5 w-5 text-red-500" fill="currentColor" viewBox="0 0 20 20">
                              <path
                                fill-rule="evenodd"
                                d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z"
                                clip-rule="evenodd"
                              />
                            </svg>
                            <span class="text-sm font-medium text-gray-900">{username}</span>
                            <span class="text-xs text-red-600">{error}</span>
                          <% _ -> %>
                            <div class="h-5 w-5 animate-spin rounded-full border-2 border-gray-300 border-t-indigo-600">
                            </div>
                            <span class="text-sm font-medium text-gray-900">{username}</span>
                            <span class="text-xs text-gray-600">Validating...</span>
                        <% end %>
                      </div>
                    </div>
                  </div>

                  <div class="mt-6 flex items-center justify-between">
                    <div class="text-sm text-gray-600">
                      <span class="font-medium text-green-600">
                        {Enum.count(@validation_results, fn {_, v} -> v.valid end)} valid
                      </span>
                      <%= if Enum.any?(@validation_results, fn {_, v} -> not v.valid end) do %>
                        <span class="mx-2">•</span>
                        <span class="font-medium text-red-600">
                          {Enum.count(@validation_results, fn {_, v} -> not v.valid end)} invalid
                        </span>
                      <% end %>
                    </div>

                    <div class="flex space-x-3">
                      <button
                        type="button"
                        phx-click="reset"
                        class="px-4 py-2 border border-gray-300 rounded-md text-sm font-medium text-gray-700 bg-white hover:bg-gray-50"
                      >
                        Clear
                      </button>
                      <button
                        type="button"
                        phx-click="start_import"
                        disabled={Enum.empty?(@parsed_usernames) or not Enum.any?(@validation_results, fn {_, v} -> v.valid end)}
                        class="px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700 disabled:bg-gray-300 disabled:cursor-not-allowed"
                      >
                        Import Valid Users ({Enum.count(@validation_results, fn {_, v} -> v.valid end)})
                      </button>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
          <%= if @import_state == :importing do %>
            <!-- Step 2: Import in progress -->
            <div class="bg-white shadow rounded-lg p-6">
              <h2 class="text-lg font-medium text-gray-900 mb-4">Importing Students...</h2>

              <div class="mb-6">
                <div class="flex items-center justify-between mb-2">
                  <span class="text-sm font-medium text-gray-700">
                    Progress: {@import_progress.progress}/{@import_progress.total}
                  </span>
                  <span class="text-sm text-gray-500">
                    {round(@import_progress.progress / @import_progress.total * 100)}%
                  </span>
                </div>
                <div class="w-full bg-gray-200 rounded-full h-2.5">
                  <div
                    class="bg-indigo-600 h-2.5 rounded-full transition-all duration-300"
                    style={"width: #{(@import_progress.progress / @import_progress.total * 100) |> round()}%"}
                  >
                  </div>
                </div>
              </div>
              <!-- Real-time results -->
              <%= if not Enum.empty?(@import_progress.results) do %>
                <div class="space-y-2 max-h-96 overflow-y-auto">
                  <div
                    :for={result <- Enum.reverse(@import_progress.results)}
                    class="flex items-center justify-between p-3 bg-gray-50 rounded-md"
                  >
                    <div class="flex items-center space-x-3">
                      <%= if result.status == :ok do %>
                        <svg class="h-5 w-5 text-green-500" fill="currentColor" viewBox="0 0 20 20">
                          <path
                            fill-rule="evenodd"
                            d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"
                            clip-rule="evenodd"
                          />
                        </svg>
                      <% else %>
                        <svg class="h-5 w-5 text-red-500" fill="currentColor" viewBox="0 0 20 20">
                          <path
                            fill-rule="evenodd"
                            d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z"
                            clip-rule="evenodd"
                          />
                        </svg>
                      <% end %>
                      <span class="text-sm font-medium text-gray-900">{result.username}</span>
                      <span class={"text-xs #{if result.status == :ok, do: "text-green-600", else: "text-red-600"}"}>
                        {result.message}
                      </span>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
          <%= if @import_state == :completed do %>
            <!-- Step 3: Import completed -->
            <div class="bg-white shadow rounded-lg p-6">
              <div class="text-center">
                <svg
                  class="mx-auto h-12 w-12 text-green-500"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
                  />
                </svg>
                <h2 class="mt-4 text-lg font-medium text-gray-900">Import Completed!</h2>

                <div class="mt-6 flex items-center justify-center space-x-8">
                  <div class="text-center">
                    <div class="text-3xl font-bold text-green-600">{@import_results.successful}</div>
                    <div class="text-sm text-gray-600">Successful</div>
                  </div>
                  <%= if @import_results.failed > 0 do %>
                    <div class="text-center">
                      <div class="text-3xl font-bold text-red-600">{@import_results.failed}</div>
                      <div class="text-sm text-gray-600">Failed</div>
                    </div>
                  <% end %>
                </div>
                <!-- Final results list -->
                <%= if @import_progress && not Enum.empty?(@import_progress.results) do %>
                  <div class="mt-6">
                    <h3 class="text-sm font-medium text-gray-900 mb-3">Import Details</h3>
                    <div class="space-y-2 max-h-96 overflow-y-auto">
                      <div
                        :for={result <- @import_progress.results}
                        class="flex items-center justify-between p-3 bg-gray-50 rounded-md text-left"
                      >
                        <div class="flex items-center space-x-3">
                          <%= if result.status == :ok do %>
                            <svg class="h-5 w-5 text-green-500" fill="currentColor" viewBox="0 0 20 20">
                              <path
                                fill-rule="evenodd"
                                d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"
                                clip-rule="evenodd"
                              />
                            </svg>
                          <% else %>
                            <svg class="h-5 w-5 text-red-500" fill="currentColor" viewBox="0 0 20 20">
                              <path
                                fill-rule="evenodd"
                                d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z"
                                clip-rule="evenodd"
                              />
                            </svg>
                          <% end %>
                          <span class="text-sm font-medium text-gray-900">{result.username}</span>
                          <span class={"text-xs #{if result.status == :ok, do: "text-green-600", else: "text-red-600"}"}>
                            {result.message}
                          </span>
                        </div>
                      </div>
                    </div>
                  </div>
                <% end %>

                <div class="mt-8 flex items-center justify-center space-x-3">
                  <button
                    type="button"
                    phx-click="reset"
                    class="px-4 py-2 border border-gray-300 rounded-md text-sm font-medium text-gray-700 bg-white hover:bg-gray-50"
                  >
                    Import More Students
                  </button>
                  <button
                    type="button"
                    phx-click="back_to_class"
                    class="px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700"
                  >
                    Back to Class
                  </button>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end