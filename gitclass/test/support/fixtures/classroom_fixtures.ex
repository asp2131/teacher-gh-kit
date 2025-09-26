defmodule Gitclass.ClassroomFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Gitclass.Classroom` context.
  """

  import Gitclass.AccountsFixtures

  @doc """
  Generate a class.
  """
  def class_fixture(attrs \\ %{}) do
    teacher = user_fixture()
    
    {:ok, class} =
      attrs
      |> Enum.into(%{
        name: "Test Class #{System.unique_integer([:positive])}",
        term: "Fall 2024",
        teacher_id: teacher.id
      })
      |> then(&Gitclass.Classroom.create_class(teacher, &1))

    class
  end
end