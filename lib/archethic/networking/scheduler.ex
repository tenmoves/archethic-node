defmodule ArchEthic.Networking.Scheduler do
  @moduledoc false

  use GenServer

  alias ArchEthic.Crypto

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Listener, as: P2PListener
  alias ArchEthic.P2P.Node

  alias ArchEthic.Networking.IPLookup
  alias ArchEthic.Networking.PortForwarding

  alias ArchEthic.TaskSupervisor

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.TransactionData

  alias ArchEthic.Utils

  alias ArchEthicWeb.Endpoint, as: WebEndpoint

  require Logger

  def start_link(arg \\ []) do
    GenServer.start_link(__MODULE__, arg)
  end

  def init(arg) do
    interval = Keyword.fetch!(arg, :interval)
    timer = schedule_update(interval)
    {:ok, %{timer: timer, interval: interval}}
  end

  def handle_info(:update, state = %{interval: interval}) do
    timer =
      case Map.get(state, :timer) do
        nil ->
          schedule_update(interval)

        old_timer ->
          Process.cancel_timer(old_timer)
          schedule_update(interval)
      end

    Task.Supervisor.start_child(TaskSupervisor, fn -> do_update() end)

    {:noreply, Map.put(state, :timer, timer)}
  end

  defp schedule_update(interval) do
    Process.send_after(self(), :update, Utils.time_offset(interval) * 1000)
  end

  defp do_update do
    Logger.info("Start networking update")
    {p2p_port, _} = open_ports()
    ip = IPLookup.get_node_ip()

    %Node{ip: prev_ip, reward_address: reward_address, transport: transport} = P2P.get_node_info()

    if ip != prev_ip do
      key_certificate = Crypto.get_key_certificate(Crypto.previous_node_public_key())

      Transaction.new(:node, %TransactionData{
        content:
          Node.encode_transaction_content(
            ip,
            p2p_port,
            transport,
            reward_address,
            key_certificate
          )
      })
      |> ArchEthic.send_new_transaction()
    else
      Logger.debug("Same IP - no need to send a new node transaction")
    end
  end

  defp open_ports do
    p2p_port = Application.get_env(:archethic, P2PListener) |> Keyword.fetch!(:port)
    web_port = Application.get_env(:archethic, WebEndpoint) |> get_in([:http, :port])
    PortForwarding.try_open_port(p2p_port, false)
    PortForwarding.try_open_port(web_port, false)

    {p2p_port, web_port}
  end
end
