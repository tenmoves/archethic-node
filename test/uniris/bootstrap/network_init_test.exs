defmodule Uniris.Bootstrap.NetworkInitTest do
  use UnirisCase

  alias Uniris.Account
  alias Uniris.Crypto

  alias Uniris.BeaconChain
  alias Uniris.BeaconChain.Slot, as: BeaconSlot
  alias Uniris.BeaconChain.Slot.TransactionSummary
  alias Uniris.BeaconChain.SlotTimer, as: BeaconSlotTimer
  alias Uniris.BeaconChain.Subset, as: BeaconSubset
  alias Uniris.BeaconChain.SubsetRegistry, as: BeaconSubsetRegistry

  alias Uniris.Bootstrap.NetworkInit

  alias Uniris.P2P
  alias Uniris.P2P.Message.GetLastTransactionAddress
  alias Uniris.P2P.Message.GetTransactionChain
  alias Uniris.P2P.Message.GetUnspentOutputs
  alias Uniris.P2P.Message.LastTransactionAddress
  alias Uniris.P2P.Message.TransactionList
  alias Uniris.P2P.Message.UnspentOutputList
  alias Uniris.P2P.Node

  alias Uniris.SharedSecrets
  alias Uniris.SharedSecrets.NodeRenewalScheduler

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.ValidationStamp
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Uniris.TransactionChain.TransactionData
  alias Uniris.TransactionChain.TransactionData.Ledger
  alias Uniris.TransactionChain.TransactionData.UCOLedger
  alias Uniris.TransactionChain.TransactionData.UCOLedger.Transfer
  alias Uniris.TransactionFactory

  import Mox

  setup do
    start_supervised!({BeaconSlotTimer, interval: "0 * * * * * *"})
    Enum.each(BeaconChain.list_subsets(), &BeaconSubset.start_link(subset: &1))
    start_supervised!({NodeRenewalScheduler, interval: "*/2 * * * * * *"})

    P2P.add_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.node_public_key(0),
      last_public_key: Crypto.node_public_key(0),
      available?: true,
      geo_patch: "AAA",
      network_patch: "AAA",
      enrollment_date: DateTime.utc_now()
    })

    MockClient
    |> stub(:send_message, fn _, %GetLastTransactionAddress{address: address} ->
      {:ok, %LastTransactionAddress{address: address}}
    end)

    :ok
  end

  test "create_storage_nonce/0 should initialize the nonce in the crypto keystore" do
    assert :ok = NetworkInit.create_storage_nonce()
  end

  test "self_validation!/2 should return a validated transaction" do
    tx =
      Transaction.new(
        :transfer,
        %TransactionData{
          ledger: %Ledger{
            uco: %UCOLedger{
              transfers: [
                %Transfer{to: "@Alice2", amount: 5_000.0}
              ]
            }
          }
        },
        "seed",
        0
      )

    unspent_outputs = [%UnspentOutput{amount: 10_000, from: tx.address, type: :UCO}]
    tx = NetworkInit.self_validation(tx, unspent_outputs)

    assert %Transaction{
             validation_stamp: %ValidationStamp{
               ledger_operations: %LedgerOperations{
                 transaction_movements: [
                   %TransactionMovement{to: "@Alice2", amount: 5_000.0, type: :UCO}
                 ],
                 unspent_outputs: [
                   # TODO: use the right change when the fee algorithm is implemented
                   %UnspentOutput{amount: 4999.99, from: _, type: :UCO}
                 ]
               }
             }
           } = tx
  end

  test "self_replication/1 should insert the transaction and add to the beacon chain" do
    MockClient
    |> stub(:send_message, fn
      _, %GetTransactionChain{} ->
        {:ok, %TransactionList{transactions: []}}

      _, %GetUnspentOutputs{} ->
        {:ok, %UnspentOutputList{unspent_outputs: []}}
    end)

    tx =
      TransactionFactory.create_valid_transaction(
        %{
          welcome_node: P2P.get_node_info(),
          coordinator_node: P2P.get_node_info(),
          storage_nodes: [P2P.get_node_info()]
        },
        [],
        type: :transfer
      )

    me = self()

    MockDB
    |> stub(:write_transaction_chain, fn _chain ->
      send(me, :write_transaction)
      :ok
    end)

    NetworkInit.self_replication(tx)

    assert_received :write_transaction

    subset = BeaconChain.subset_from_address(tx.address)
    [{pid, _}] = Registry.lookup(BeaconSubsetRegistry, subset)

    tx_address = tx.address

    %{
      current_slot: %BeaconSlot{
        transaction_summaries: [
          %TransactionSummary{address: ^tx_address}
        ]
      }
    } = :sys.get_state(pid)
  end

  test "init_node_shared_secrets_chain/1 should create node shared secrets transaction chain, load daily nonce and authorize node" do
    MockClient
    |> stub(:send_message, fn
      _, %GetTransactionChain{} ->
        {:ok, %TransactionList{transactions: []}}

      _, %GetUnspentOutputs{} ->
        {:ok, %UnspentOutputList{unspent_outputs: []}}
    end)

    me = self()

    P2P.add_node(%Node{
      first_public_key: Crypto.node_public_key(),
      last_public_key: Crypto.node_public_key(),
      ip: {127, 0, 0, 1},
      port: 3000,
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now(),
      geo_patch: "AAA",
      network_patch: "AAA"
    })

    MockDB
    |> expect(:write_transaction_chain, fn [tx] ->
      send(me, {:transaction, tx})
      :ok
    end)

    MockCrypto
    |> stub(:decrypt_and_set_node_shared_secrets_network_pool_seed, fn _, _ ->
      send(me, :set_network_pool)
      :ok
    end)
    |> stub(:decrypt_and_set_daily_nonce_seed, fn _, _, _ ->
      send(me, :set_daily_nonce)
      :ok
    end)
    |> stub(:decrypt_and_set_node_shared_secrets_transaction_seed, fn _, _ ->
      send(me, :set_transaction_seed)
      :ok
    end)

    NetworkInit.init_node_shared_secrets_chain()

    assert_receive {:transaction, %Transaction{type: :node_shared_secrets}}
    assert_receive :set_network_pool
    assert_receive :set_daily_nonce
    assert_receive :set_transaction_seed

    assert %Node{authorized?: true} = P2P.get_node_info()
  end

  test "init_genesis_wallets/1 should initialize genesis wallets" do
    MockClient
    |> stub(:send_message, fn
      _, %GetTransactionChain{} ->
        {:ok, %TransactionList{transactions: []}}

      _, %GetUnspentOutputs{} ->
        {:ok, %UnspentOutputList{unspent_outputs: []}}
    end)

    P2P.add_node(%Node{
      first_public_key: Crypto.node_public_key(),
      last_public_key: Crypto.node_public_key(),
      ip: {127, 0, 0, 1},
      port: 3000,
      available?: true,
      enrollment_date: DateTime.utc_now(),
      network_patch: "AAA"
    })

    NetworkInit.init_genesis_wallets()

    funding_address =
      "002E354A95241E867C836E8BBBBF6F9BF2450860BA28B1CF24B734EF67FF49169E"
      |> Base.decode16!()
      |> Crypto.hash()

    assert %{uco: 3.82e9} = Account.get_balance(funding_address)
    assert %{uco: 1.46e9} = Account.get_balance(SharedSecrets.get_network_pool_address())
  end
end
