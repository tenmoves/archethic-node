defmodule Archethic.SelfRepair.RepairWorker do
  @moduledoc false

  alias Archethic.Crypto
  alias Archethic.SelfRepair
  alias Archethic.SelfRepair.RepairRegistry
  alias Archethic.SelfRepair.NotifierSupervisor

  use GenServer, restart: :transient
  @vsn Mix.Project.config()[:version]

  require Logger

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, [])
  end

  @doc """
  Add addresses to repair in RepairWorker.
  If the RepairWorker does not exist yet, it is created.
  The RepairWorker will run until there is no more address to repair.
  """
  @spec repair_addresses(
          Crypto.prepended_hash(),
          Crypto.prepended_hash() | list(Crypto.prepended_hash()) | nil,
          list(Crypto.prepended_hash())
        ) :: :ok
  def repair_addresses(genesis_address, storage_addresses, io_addresses) do
    storage_addresses = List.wrap(storage_addresses)

    case Registry.lookup(RepairRegistry, genesis_address) do
      [{pid, _}] ->
        GenServer.cast(pid, {:add_address, storage_addresses, io_addresses})

      _ ->
        {:ok, _} =
          DynamicSupervisor.start_child(
            NotifierSupervisor,
            {__MODULE__,
             [
               first_address: genesis_address,
               storage_addresses: storage_addresses,
               io_addresses: io_addresses
             ]}
          )

        :ok
    end
  end

  def init(args) do
    first_address = Keyword.fetch!(args, :first_address)
    storage_addresses = Keyword.fetch!(args, :storage_addresses)
    io_addresses = Keyword.fetch!(args, :io_addresses)

    Registry.register(RepairRegistry, first_address, [])

    Logger.info(
      "Notifier Repair Worker start with storage_addresses #{Enum.map_join(storage_addresses, ", ", &Base.encode16(&1))}, " <>
        "io_addresses #{inspect(Enum.map(io_addresses, &Base.encode16(&1)))}",
      address: Base.encode16(first_address)
    )

    data = %{
      storage_addresses: storage_addresses,
      io_addresses: io_addresses
    }

    {:ok, start_repair(data)}
  end

  def handle_cast({:add_address, storage_addresses, io_addresses}, data) do
    new_data =
      if storage_addresses != [],
        do: Map.update!(data, :storage_addresses, &((&1 ++ storage_addresses) |> Enum.uniq())),
        else: data

    new_data =
      if io_addresses != [],
        do: Map.update!(new_data, :io_addresses, &((&1 ++ io_addresses) |> Enum.uniq())),
        else: new_data

    {:noreply, new_data}
  end

  def handle_info(
        {:DOWN, _ref, :process, pid, _normal},
        data = %{task: task_pid, storage_addresses: [], io_addresses: []}
      )
      when pid == task_pid do
    {:stop, :normal, data}
  end

  def handle_info(
        {:DOWN, _ref, :process, pid, _normal},
        data = %{task: task_pid}
      )
      when pid == task_pid do
    {:noreply, start_repair(data)}
  end

  def handle_info(_, data), do: {:noreply, data}

  defp start_repair(
         data = %{
           storage_addresses: [],
           io_addresses: [address | rest]
         }
       ) do
    pid = repair_task(address, false)

    data
    |> Map.put(:io_addresses, rest)
    |> Map.put(:task, pid)
  end

  defp start_repair(
         data = %{
           storage_addresses: [address | rest]
         }
       ) do
    pid = repair_task(address, true)

    data
    |> Map.put(:storage_addresses, rest)
    |> Map.put(:task, pid)
  end

  defp repair_task(address, storage?) do
    %Task{pid: pid} =
      Task.async(fn ->
        SelfRepair.replicate_transaction(address, storage?)
      end)

    pid
  end
end
