defmodule ArchEthic.Bootstrap.TransactionHandler do
  @moduledoc false

  alias ArchEthic.Crypto

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Message.NewTransaction
  alias ArchEthic.P2P.Message.Ok
  alias ArchEthic.P2P.Node

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.TransactionData

  require Logger

  @doc """
  Send a transaction to the network towards a welcome node
  """
  @spec send_transaction(Transaction.t(), list(Node.t())) :: :ok | {:error, :network_issue}
  def send_transaction(tx = %Transaction{address: address}, nodes) do
    Logger.info("Send node transaction...",
      transaction_address: Base.encode16(address),
      transaction_type: "node"
    )

    Logger.info("Waiting transaction replication",
      transaction_address: Base.encode16(address),
      transaction_type: "node"
    )

    do_send_transaction(nodes, tx)
  end

  defp do_send_transaction([node | rest], tx) do
    case P2P.send_message(node, %NewTransaction{transaction: tx}) do
      {:ok, %Ok{}} ->
        :ok

      {:error, _} = e ->
        Logger.error("Cannot send node transaction - #{inspect(e)}",
          node: Base.encode16(node.first_public_key)
        )

        do_send_transaction(rest, tx)
    end
  end

  defp do_send_transaction([], _), do: {:error, :network_issue}

  @doc """
  Create a new node transaction
  """
  @spec create_node_transaction(
          :inet.ip_address(),
          :inet.port_number(),
          P2P.supported_transport(),
          Crypto.versioned_hash()
        ) ::
          Transaction.t()
  def create_node_transaction(ip = {_, _, _, _}, port, transport, reward_address)
      when is_number(port) and port >= 0 and is_binary(reward_address) do
    key_certificate = Crypto.get_key_certificate(Crypto.last_node_public_key())

    Transaction.new(:node, %TransactionData{
      content:
        Node.encode_transaction_content(ip, port, transport, reward_address, key_certificate)
    })
  end
end
