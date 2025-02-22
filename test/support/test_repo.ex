defmodule ArangoXEcto.Integration.Repo do
  defmacro __using__(opts) do
    quote do
      use Ecto.Repo, unquote(opts)

      @query_event __MODULE__
                   |> Module.split()
                   |> Enum.map(&(&1 |> Macro.underscore() |> String.to_atom()))
                   |> Kernel.++([:query])

      def init(_, opts) do
        fun = &ArangoXEcto.Integration.Repo.handle_event/4
        :telemetry.attach_many(__MODULE__, [[:custom], @query_event], fun, :ok)
        {:ok, opts}
      end
    end
  end

  def handle_event(event, latency, metadata, _config) do
    handler = Process.delete(:telemetry) || fn _, _, _ -> :ok end
    handler.(event, latency, metadata)
  end
end

defmodule MigrationsAgent do
  use Agent

  def start_link(versions) do
    Agent.start_link(fn -> versions end, name: __MODULE__)
  end

  def get do
    Agent.get(__MODULE__, & &1)
  end

  def up(version, opts) do
    Agent.update(__MODULE__, &[{version, opts[:prefix]} | &1])
  end

  def down(version, opts) do
    Agent.update(__MODULE__, &List.delete(&1, {version, opts[:prefix]}))
  end
end

defmodule ArangoXEcto.TestAdapter do
  @behaviour Ecto.Adapter
  @behaviour Ecto.Adapter.Queryable
  @behaviour Ecto.Adapter.Schema
  @behaviour Ecto.Adapter.Transaction

  defmacro __before_compile__(_opts), do: :ok
  def ensure_all_started(_, _), do: {:ok, []}

  def init(_opts) do
    child_spec = Supervisor.child_spec({Task, fn -> :timer.sleep(:infinity) end}, [])
    {:ok, child_spec, %{meta: :meta}}
  end

  def checkout(_, _, _), do: raise("not implemented")
  def checked_out?(_), do: raise("not implemented")
  def delete(_, _, _, _, _), do: raise("not implemented")
  def insert_all(_, _, _, _, _, _, _, _), do: raise("not implemented")
  def rollback(_, _), do: raise("not implemented")
  def stream(_, _, _, _, _), do: raise("not implemented")
  def update(_, _, _, _, _, _), do: raise("not implemented")

  ## Types

  def loaders(_primitive, type), do: [type]
  def dumpers(_primitive, type), do: [type]
  def autogenerate(_), do: nil

  ## Queryable

  def prepare(operation, query), do: {:nocache, {operation, query}}

  # Migration emulation

  def execute(_, _, {:nocache, {:all, query}}, _, opts) do
    %{from: %{source: {"_migrations", _}}} = query
    true = opts[:schema_migration]
    versions = MigrationsAgent.get()
    {length(versions), Enum.map(versions, &[elem(&1, 0)])}
  end

  def execute(_, _, {:nocache, {:delete_all, query}}, params, opts) do
    %{from: %{source: {"_migrations", _}}} = query
    [version] = params
    true = opts[:schema_migration]
    MigrationsAgent.down(version, opts)
    {1, nil}
  end

  def insert(_, %{source: "_migrations"}, val, _, _, opts) do
    true = opts[:schema_migration]
    version = Keyword.fetch!(val, :version)
    MigrationsAgent.up(version, opts)
    {:ok, []}
  end

  def in_transaction?(_), do: Process.get(:in_transaction?) || false

  def transaction(mod, _opts, fun) do
    Process.put(:in_transaction?, true)
    send(test_process(), {:transaction, mod, fun})
    {:ok, fun.()}
  after
    Process.put(:in_transaction?, false)
  end

  def execute_ddl(_, command, _) do
    Process.put(:last_command, command)
    {:ok, [{:info, "execute ddl", %{command: command}}]}
  end

  defp test_process do
    get_config(:test_process, self())
  end

  defp get_config(name, default) do
    :arangox_ecto
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(name, default)
  end
end

defmodule ArangoXEcto.Integration.PoolRepo do
  use ArangoXEcto.Integration.Repo, otp_app: :arangox_ecto, adapter: ArangoXEcto.Adapter
end

defmodule ArangoXEcto.Integration.TestRepo do
  use ArangoXEcto.Integration.Repo,
    otp_app: :arangox_ecto,
    adapter: ArangoXEcto.Adapter
end

defmodule ArangoXEcto.Integration.DynamicRepo do
  use ArangoXEcto.Integration.Repo,
    otp_app: :arangox_ecto,
    adapter: ArangoXEcto.Adapter
end

defmodule ArangoXEcto.TestRepo do
  use Ecto.Repo, otp_app: :arangox_ecto, adapter: ArangoXEcto.TestAdapter

  def default_options(_operation) do
    Process.get(:repo_default_options, [])
  end
end

defmodule ArangoXEcto.MigrationTestRepo do
  use Ecto.Repo, otp_app: :arangox_ecto, adapter: ArangoXEcto.TestAdapter
end

ArangoXEcto.TestRepo.start_link()
ArangoXEcto.TestRepo.start_link(name: :tenant_db)
ArangoXEcto.MigrationTestRepo.start_link()
