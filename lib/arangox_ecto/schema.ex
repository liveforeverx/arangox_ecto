defmodule ArangoXEcto.Schema do
  @moduledoc """
  This module is a helper to automatically specify the primary key.

  The primary key is the Arango `_key` field but the _id field is also provided.

  Schema modules should use this module by add `use ArangoXEcto.Schema` to the module. The only
  exception to this is if the collection is an edge collection, in that case refer to ArangoXEcto.Edge.

  ## Example

      defmodule MyProject.Accounts.User do
        use ArangoXEcto.Schema
        import Ecto.Changeset

        schema "users" do
          field :first_name, :string
          field :last_name, :string

          timestamps()
        end

        @doc false
        def changeset(app, attrs) do
          app
          |> cast(attrs, [:first_name, :last_name])
          |> validate_required([:first_name, :last_name])
        end
      end
  """

  defmacro __using__(_) do
    quote do
      use Ecto.Schema
      import unquote(__MODULE__)

      @primary_key {:id, :binary_id, autogenerate: true, source: :_key}
      @foreign_key_type :binary_id
    end
  end

  @doc """
  Defines an outgoing relationship of many objects
  """
  defmacro many_outgoing(name, target, opts \\ []) do
    quote do
      opts = unquote(opts)

      many_to_many(unquote(name), unquote(target),
        join_through:
          Keyword.get(opts, :edge, ArangoXEcto.edge_module(__MODULE__, unquote(target))),
        join_keys: [_from: :id, _to: :id],
        on_replace: :delete
      )
    end
  end

  @doc """
  Defines an outgoing relationship of one object
  """
  # TODO: Setup only one outgoing
  defmacro one_outgoing(name, target, opts \\ []) do
    quote do
      opts = unquote(opts)

      has_one(unquote(name), unquote(target),
        foreign_key: unquote(name) |> build_foreign_key(),
        on_replace: :delete
      )
    end
  end

  @doc """
  Defines an incoming relationship
  """
  defmacro incoming(name, source, opts \\ []) do
    quote do
      opts = unquote(opts)

      many_to_many(unquote(name), unquote(source),
        join_through:
          Keyword.get(opts, :edge, ArangoXEcto.edge_module(__MODULE__, unquote(source))),
        join_keys: [_to: :id, _from: :id],
        on_replace: :delete
      )
    end
  end

  @spec build_foreign_key(atom()) :: atom()
  def build_foreign_key(name) do
    name
    |> Atom.to_string()
    |> Kernel.<>("_id")
    |> String.to_atom()
  end
end
