defmodule Gitclass.Classroom do
  @moduledoc """
  The Classroom context for managing classes and students.
  """

  import Ecto.Query, warn: false
  alias Gitclass.Repo
  alias Gitclass.Classroom.{Class, ClassStudent, CommitActivity}
  alias Gitclass.Accounts.User

  @doc """
  Returns the list of classes for a teacher with student count.
  """
  def list_classes_for_teacher(%User{} = teacher) do
    Class
    |> where([c], c.teacher_id == ^teacher.id)
    |> join(:left, [c], s in ClassStudent, on: c.id == s.class_id)
    |> group_by([c], c.id)
    |> select([c, s], %{c | student_count: count(s.id)})
    |> order_by([c], desc: c.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single class.
  """
  def get_class!(id), do: Repo.get!(Class, id)

  @doc """
  Gets a class with all students preloaded.
  """
  def get_class_with_students!(id) do
    Class
    |> where([c], c.id == ^id)
    |> preload(:students)
    |> Repo.one!()
  end

  @doc """
  Creates a class.
  """
  def create_class(%User{} = teacher, attrs \\ %{}) do
    # Ensure consistent key types - convert to string keys if attrs uses string keys
    attrs_with_teacher =
      if is_map_key(attrs, "name") or is_map_key(attrs, :name) do
        # If attrs has string keys or atom keys, add teacher_id with matching key type
        if is_map_key(attrs, "name") do
          Map.put(attrs, "teacher_id", teacher.id)
        else
          Map.put(attrs, :teacher_id, teacher.id)
        end
      else
        Map.put(attrs, :teacher_id, teacher.id)
      end

    %Class{}
    |> Class.changeset(attrs_with_teacher)
    |> Repo.insert()
  end

  @doc """
  Updates a class.
  """
  def update_class(%Class{} = class, attrs) do
    class
    |> Class.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a class.
  """
  def delete_class(%Class{} = class) do
    Repo.delete(class)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking class changes.
  """
  def change_class(%Class{} = class, attrs \\ %{}) do
    Class.changeset(class, attrs)
  end

  @doc """
  Adds a student to a class.
  """
  def add_student_to_class(%Class{} = class, student_username, attrs \\ %{}) do
    %ClassStudent{}
    |> ClassStudent.changeset(
      attrs
      |> Map.put(:class_id, class.id)
      |> Map.put(:student_github_username, student_username)
      |> Map.put(:added_at, DateTime.utc_now())
    )
    |> Repo.insert()
  end

  @doc """
  Removes a student from a class.
  """
  def remove_student_from_class(%Class{} = class, student_username) do
    ClassStudent
    |> where([s], s.class_id == ^class.id and s.student_github_username == ^student_username)
    |> Repo.delete_all()
  end

  @doc """
  Gets a student in a class.
  """
  def get_class_student(class_id, student_username) do
    ClassStudent
    |> where([s], s.class_id == ^class_id and s.student_github_username == ^student_username)
    |> Repo.one()
  end

  @doc """
  Updates a class student.
  """
  def update_class_student(%ClassStudent{} = student, attrs) do
    student
    |> ClassStudent.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Lists all students in a class.
  """
  def list_class_students(%Class{} = class) do
    ClassStudent
    |> where([s], s.class_id == ^class.id)
    |> order_by([s], asc: s.student_name)
    |> Repo.all()
  end

  @doc """
  Creates or updates commit activity for a student.
  """
  def upsert_commit_activity(attrs) do
    %CommitActivity{}
    |> CommitActivity.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:commit_count, :last_commit_at, :updated_at]},
      conflict_target: [:class_id, :student_username, :commit_date, :repository_name]
    )
  end

  @doc """
  Gets commit activities for a student in a date range.
  """
  def get_commit_activities(class_id, student_username, date_range) do
    CommitActivity
    |> where([ca], ca.class_id == ^class_id and ca.student_username == ^student_username)
    |> where([ca], ca.commit_date >= ^date_range.first and ca.commit_date <= ^date_range.last)
    |> order_by([ca], asc: ca.commit_date)
    |> Repo.all()
  end

  @doc """
  Gets all active classes (classes that have students).
  """
  def list_active_classes do
    Class
    |> join(:inner, [c], s in ClassStudent, on: c.id == s.class_id)
    |> distinct([c], c.id)
    |> Repo.all()
  end
end
