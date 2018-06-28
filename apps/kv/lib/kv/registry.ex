defmodule KV.Registry do
  use GenServer

  ## Client API

  @doc """
  Starts the registry

  `:name is required`
  """
  def start_link(opts) do
    # 1. Pass the name to GenServer's init
    server = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, server, opts)
  end

  @doc """
  Looks up the bucket pid for `name` stored in `server`.

  Returns `{:ok, pid}` if the bucket exists, `:error` otherwise.
  """
  def lookup(server, name) do
    # GenServer.call(server, {:lookup, name})
    # 2. Lookup is now done directly in the ETS, without accessing the server
    case :ets.lookup(server, name) do
      [{^name, pid}] -> {:ok, pid}
      [] -> :error
    end
  end

  @doc """
  Ensures there is a bucket associated with the given `name` in `server`.
  """
  def create(server, name) do
    GenServer.call(server, {:create, name})
  end

  @doc """
  Stops the registry
  """
  def stop(server) do
    GenServer.stop(server)
  end

  ## Server Callbacks

  def init(table) do
    # names = %{}
    # 3. We have replaced the names mapp by the ETS table
    names = :ets.new(table, [:named_table, read_concurrency: true])
    refs = %{}
    {:ok, {names, refs}}
  end

  # 4. handle_call function no longer needed since we directly lookup in the ETS
  # @doc """
  # Sync Op to handle lookup of bucket name
  # """
  # def handle_call({:lookup, name}, _from, {names, _} = state) do
  #   {:reply, Map.fetch(names, name), state}
  # end

  @doc """
  Async Op to handle bucket creation
  Now is a sync op
  """
  def handle_call({:create, name}, _from, {names, refs}) do
    # if Map.has_key?(names, name) do
    #   {:noreply, {names, refs}}
    # else
    #   {:ok, pid} = DynamicSupervisor.start_child(KV.BucketSupervisor, KV.Bucket)
    #   ref = Process.monitor(pid)
    #   refs = Map.put(refs, ref, name)
    #   names = Map.put(names, name, pid)
    #   {:noreply, {names, refs}}
    # end

    # 5. Read and write to the ETS table instead of the map
    case lookup(names, name) do
      {:ok, pid} -> 
        {:reply, pid, {names, refs}}
      :error ->
        {:ok, pid} = DynamicSupervisor.start_child(KV.BucketSupervisor, KV.Bucket)
        ref = Process.monitor(pid)
        refs = Map.put(refs, ref, name)
        :ets.insert(names, {name, pid})
        {:reply, pid, {names, refs}}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, {names, refs}) do
    # 6. Delete from the ETS table instead of the map
    {name, refs} = Map.pop(refs, ref)
    # names = Map.delete(names, name)
    :ets.delete(names, name)
    {:noreply, {names, refs}}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
