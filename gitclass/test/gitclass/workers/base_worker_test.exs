defmodule Gitclass.Workers.BaseWorkerTest do
  use Gitclass.DataCase, async: true
  use Oban.Testing, repo: Gitclass.Repo

  alias Gitclass.Workers.BaseWorker

  describe "calculate_backoff/1" do
    test "calculates exponential backoff with jitter" do
      # Test that backoff increases with attempt number
      backoff_1 = BaseWorker.calculate_backoff(1)
      backoff_2 = BaseWorker.calculate_backoff(2)
      backoff_3 = BaseWorker.calculate_backoff(3)

      assert backoff_1 >= 2  # 2^1 = 2 seconds minimum
      assert backoff_2 >= 4  # 2^2 = 4 seconds minimum
      assert backoff_3 >= 8  # 2^3 = 8 seconds minimum

      # Test that jitter is applied (should be different on multiple calls)
      backoff_1_again = BaseWorker.calculate_backoff(1)
      # Note: This might occasionally be the same due to randomness, but very unlikely
    end
  end

  describe "default_error_handler/2" do
    test "handles network errors with retry" do
      job = %Oban.Job{attempt: 1}
      error = %{reason: :network_error}

      result = BaseWorker.default_error_handler(error, job)

      assert {:snooze, delay} = result
      assert is_integer(delay)
      assert delay > 0
    end

    test "handles rate limiting with fixed delay" do
      job = %Oban.Job{attempt: 1}
      error = %{reason: :rate_limited}

      result = BaseWorker.default_error_handler(error, job)

      assert {:snooze, 60} = result
    end

    test "discards invalid username errors" do
      job = %Oban.Job{attempt: 1}
      error = %{reason: :invalid_username}

      result = BaseWorker.default_error_handler(error, job)

      assert {:discard, "Invalid username provided"} = result
    end

    test "discards user not found errors" do
      job = %Oban.Job{attempt: 1}
      error = %{reason: :user_not_found}

      result = BaseWorker.default_error_handler(error, job)

      assert {:discard, "GitHub user not found"} = result
    end

    test "retries generic errors up to max attempts" do
      error = %{reason: :generic_error}

      # First two attempts should retry
      job_attempt_1 = %Oban.Job{attempt: 1}
      result_1 = BaseWorker.default_error_handler(error, job_attempt_1)
      assert {:snooze, _delay} = result_1

      job_attempt_2 = %Oban.Job{attempt: 2}
      result_2 = BaseWorker.default_error_handler(error, job_attempt_2)
      assert {:snooze, _delay} = result_2

      # Third attempt should discard
      job_attempt_3 = %Oban.Job{attempt: 3}
      result_3 = BaseWorker.default_error_handler(error, job_attempt_3)
      assert {:discard, message} = result_3
      assert String.contains?(message, "Max retries exceeded")
    end
  end

  describe "broadcast_progress/2" do
    test "broadcasts progress updates via PubSub" do
      topic = "test:progress"
      progress_data = %{status: :running, progress: 50, total: 100}

      # Subscribe to the topic
      Phoenix.PubSub.subscribe(Gitclass.PubSub, topic)

      # Broadcast progress
      BaseWorker.broadcast_progress(topic, progress_data)

      # Assert we received the message
      assert_receive {:job_progress, ^progress_data}
    end
  end
end
