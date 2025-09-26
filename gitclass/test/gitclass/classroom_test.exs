defmodule Gitclass.ClassroomTest do
  use Gitclass.DataCase

  alias Gitclass.Classroom

  describe "classes" do
    alias Gitclass.Classroom.Class

    import Gitclass.AccountsFixtures
    import Gitclass.ClassroomFixtures

    test "list_classes_for_teacher/1 returns all classes for teacher" do
      teacher = user_fixture()
      {:ok, class} = Classroom.create_class(teacher, %{name: "Test Class", term: "Fall 2024"})
      assert Classroom.list_classes_for_teacher(teacher) == [class]
    end

    test "get_class!/1 returns the class with given id" do
      class = class_fixture()
      assert Classroom.get_class!(class.id) == class
    end

    test "create_class/2 with valid data creates a class" do
      teacher = user_fixture()
      valid_attrs = %{name: "JavaScript Fundamentals", term: "Fall 2024"}

      assert {:ok, %Class{} = class} = Classroom.create_class(teacher, valid_attrs)
      assert class.name == "JavaScript Fundamentals"
      assert class.term == "Fall 2024"
      assert class.teacher_id == teacher.id
    end

    test "create_class/2 with invalid data returns error changeset" do
      teacher = user_fixture()
      assert {:error, %Ecto.Changeset{}} = Classroom.create_class(teacher, %{name: nil})
    end
  end

  describe "class_students" do
    import Gitclass.AccountsFixtures
    import Gitclass.ClassroomFixtures

    test "add_student_to_class/3 adds student to class" do
      teacher = user_fixture()
      class = class_fixture(%{teacher_id: teacher.id})
      
      assert {:ok, student} = Classroom.add_student_to_class(class, "testuser", %{
        student_name: "Test Student"
      })
      
      assert student.student_github_username == "testuser"
      assert student.student_name == "Test Student"
      assert student.class_id == class.id
    end

    test "list_class_students/1 returns all students in class" do
      teacher = user_fixture()
      class = class_fixture(%{teacher_id: teacher.id})
      {:ok, _student} = Classroom.add_student_to_class(class, "testuser")
      
      students = Classroom.list_class_students(class)
      assert length(students) == 1
      assert hd(students).student_github_username == "testuser"
    end
  end
end