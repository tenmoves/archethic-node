defmodule UnirisCore.Storage.Cache do
  @moduledoc false

  alias UnirisCore.Transaction
  alias UnirisCore.Storage.Backend

  @transaction_table :uniris_transactions
  @node_table :uniris_node_txs_lookup
  @unspent_outputs_table :uniris_unspent_outputs_txs_lookup
  @shared_secrets_table :uniris_shared_secrets_txs_lookup
  @ko_transaction_table :uniris_ko_txs_lookup

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    :ets.new(@transaction_table, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(@node_table, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(@unspent_outputs_table, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(@ko_transaction_table, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(@shared_secrets_table, [:bag, :named_table, :public, read_concurrency: true])

    Enum.each(Backend.list_transactions(), fn tx ->
      :ets.insert(@transaction_table, {tx.address, tx})
      index_transaction(tx)
    end)

    {:ok, []}
  end

  defp index_transaction(%Transaction{
         address: tx_address,
         type: :node,
         previous_public_key: previous_public_key
       }) do
    case :ets.lookup(@node_table, previous_public_key) do
      [] ->
        :ets.insert(@node_table, {previous_public_key, tx_address})

      [{genesis, _}] ->
        :ets.insert(@node_table, {genesis, tx_address})
    end
  end

  defp index_transaction(%Transaction{address: tx_address, type: :node_shared_secrets}) do
    case :ets.lookup(@shared_secrets_table, :first_node_shared_secrets) do
      [] ->
        :ets.insert(@shared_secrets_table, {:last_node_shared_secrets, tx_address})
        :ets.insert(@shared_secrets_table, {:first_node_shared_secrets, tx_address})

      _ ->
        :ets.delete(@shared_secrets_table, :last_node_shared_secrets)
        :ets.insert(@shared_secrets_table, {:last_node_shared_secrets, tx_address})
    end
  end

  defp index_transaction(%Transaction{address: tx_address, type: :origin_shared_secrets}) do
    :ets.insert(@shared_secrets_table, {:origin_shared_secrets, tx_address})
  end

  defp index_transaction(%Transaction{address: tx_address, data: %{ledger: ledger}}) do
    case ledger do
      %{uco: %{transfers: uco_transfers}} ->
        Enum.each(uco_transfers, fn %{to: recipient} ->
          :ets.insert(@unspent_outputs_table, {recipient, tx_address})
        end)

      _ ->
        :ok
    end
  end

  defp index_transaction(_), do: :ok

  def store_transaction(tx = %Transaction{address: tx_address}) do
    true = :ets.insert(@transaction_table, {tx_address, tx})
    index_transaction(tx)
    :ok
  end

  def store_ko_transaction(%Transaction{
        address: tx_address,
        validation_stamp: validation_stamp,
        cross_validation_stamps: stamps
      }) do
    inconsistencies =
      stamps
      |> Enum.map(fn {_, inconsistencies, _} -> inconsistencies end)
      |> Enum.uniq()

    true = :ets.insert(@ko_transaction_table, {tx_address, validation_stamp, inconsistencies})
    :ok
  end

  def get_transaction(tx_address) do
    case :ets.lookup(@transaction_table, tx_address) do
      [{_, tx}] ->
        tx

      _ ->
        nil
    end
  end

  def node_transactions() do
    case :ets.select(@node_table, [{{:_, :"$1"}, [], [:"$1"]}]) do
      [] ->
        []

      addresses ->
        Enum.map(addresses, &get_transaction/1)
    end
  end

  def origin_shared_secrets_transactions() do
    case :ets.lookup(@shared_secrets_table, :origin_shared_secrets) do
      [] ->
        []

      transactions ->
        Enum.map(transactions, fn {_, address} ->
          [{_, tx}] = :ets.lookup(@transaction_table, address)
          tx
        end)
    end
  end

  def ko_transaction?(address) do
    case :ets.lookup(@ko_transaction_table, address) do
      [] ->
        false

      _ ->
        true
    end
  end

  def get_unspent_outputs(address) do
    case :ets.lookup(@unspent_outputs_table, address) do
      [] ->
        []

      unspent_outputs ->
        Enum.map(unspent_outputs, fn {_, address} ->
          [{_, tx}] = :ets.lookup(@transaction_table, address)
          tx
        end)
    end
  end

  def last_node_shared_secrets_transaction() do
    case :ets.lookup(@shared_secrets_table, :last_node_shared_secrets) do
      [{_, address}] ->
        [{_, tx}] = :ets.lookup(@transaction_table, address)
        tx

      _ ->
        nil
    end
  end
end
