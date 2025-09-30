Mox.defmock(Gitclass.GitHubMock, for: Gitclass.GitHubBehaviour)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Gitclass.Repo, :manual)
