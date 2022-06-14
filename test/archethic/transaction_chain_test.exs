defmodule Archethic.TransactionChainTest do
  use ArchethicCase

  alias Archethic.Crypto

  alias Archethic.P2P
  alias Archethic.P2P.Message.GetTransaction
  alias Archethic.P2P.Message.GetTransactionChain
  alias Archethic.P2P.Message.GetTransactionChainLength
  alias Archethic.P2P.Message.GetLastTransactionAddress
  alias Archethic.P2P.Message.GetTransactionInputs
  alias Archethic.P2P.Message.GetUnspentOutputs
  alias Archethic.P2P.Message.NotFound
  alias Archethic.P2P.Message.LastTransactionAddress
  alias Archethic.P2P.Message.TransactionChainLength
  alias Archethic.P2P.Message.TransactionList
  alias Archethic.P2P.Message.TransactionInputList
  alias Archethic.P2P.Message.UnspentOutputList
  alias Archethic.P2P.Node

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionInput

  doctest TransactionChain

  import Mox

  test "resolve_last_address/1 should retrieve the last address for a chain" do
    MockClient
    |> stub(:send_message, fn
      _, %GetLastTransactionAddress{timestamp: ~U[2021-03-25 15:11:29Z]}, _ ->
        {:ok, %LastTransactionAddress{address: "@Alice1"}}

      _, %GetLastTransactionAddress{timestamp: ~U[2021-03-25 15:12:29Z]}, _ ->
        {:ok, %LastTransactionAddress{address: "@Alice2"}}
    end)

    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.first_node_public_key(),
      last_public_key: Crypto.first_node_public_key(),
      available?: true,
      geo_patch: "AAA",
      network_patch: "AAA",
      authorized?: true,
      authorization_date: DateTime.utc_now()
    })

    assert {:ok, "@Alice1"} =
             TransactionChain.resolve_last_address("@Alice1", ~U[2021-03-25 15:11:29Z])

    assert {:ok, "@Alice2"} =
             TransactionChain.resolve_last_address("@Alice1", ~U[2021-03-25 15:12:29Z])
  end

  describe "fetch_transaction_remotely/2" do
    test "should get the transaction" do
      nodes = [
        %Node{
          first_public_key: "node1",
          last_public_key: "node1",
          ip: {127, 0, 0, 1},
          port: 3000
        },
        %Node{
          first_public_key: "node2",
          last_public_key: "node2",
          ip: {127, 0, 0, 1},
          port: 3001
        },
        %Node{
          first_public_key: "node3",
          last_public_key: "node3",
          ip: {127, 0, 0, 1},
          port: 3002
        }
      ]

      Enum.each(nodes, &P2P.add_and_connect_node/1)

      MockClient
      |> stub(:send_message, fn _, %GetTransaction{address: _}, _ ->
        {:ok, %Transaction{}}
      end)

      assert {:ok, %Transaction{}} = TransactionChain.fetch_transaction_remotely("Alice1", nodes)
    end

    test "should resolve and get tx if one tx is returned" do
      nodes = [
        %Node{
          first_public_key: "node1",
          last_public_key: "node1",
          ip: {127, 0, 0, 1},
          port: 3000
        },
        %Node{
          first_public_key: "node2",
          last_public_key: "node2",
          ip: {127, 0, 0, 1},
          port: 3001
        },
        %Node{
          first_public_key: "node3",
          last_public_key: "node3",
          ip: {127, 0, 0, 1},
          port: 3002
        }
      ]

      Enum.each(nodes, &P2P.add_and_connect_node/1)

      MockClient
      |> stub(:send_message, fn
        %Node{port: 3000}, %GetTransaction{address: _}, _ ->
          {:ok, %NotFound{}}

        %Node{port: 3001}, %GetTransaction{address: _}, _ ->
          {:ok, %Transaction{}}

        %Node{port: 3002}, %GetTransaction{address: _}, _ ->
          {:ok, %NotFound{}}
      end)

      assert {:ok, %Transaction{}} = TransactionChain.fetch_transaction_remotely("Alice1", nodes)
    end
  end

  describe "stream_remotely/2" do
    test "should get the transaction chain" do
      nodes = [
        %Node{
          first_public_key: "node1",
          last_public_key: "node1",
          ip: {127, 0, 0, 1},
          port: 3000
        },
        %Node{
          first_public_key: "node2",
          last_public_key: "node2",
          ip: {127, 0, 0, 1},
          port: 3001
        },
        %Node{
          first_public_key: "node3",
          last_public_key: "node3",
          ip: {127, 0, 0, 1},
          port: 3002
        }
      ]

      Enum.each(nodes, &P2P.add_and_connect_node/1)

      MockClient
      |> stub(:send_message, fn _, %GetTransactionChain{address: _}, _ ->
        {:ok,
         %TransactionList{
           transactions: [
             %Transaction{}
           ]
         }}
      end)

      assert 1 =
               TransactionChain.stream_remotely("Alice1", nodes)
               |> Enum.to_list()
               |> List.first()
               |> length()
    end

    test "should resolve the longest chain" do
      nodes = [
        %Node{
          first_public_key: "node1",
          last_public_key: "node1",
          ip: {127, 0, 0, 1},
          port: 3000
        },
        %Node{
          first_public_key: "node2",
          last_public_key: "node2",
          ip: {127, 0, 0, 1},
          port: 3001
        },
        %Node{
          first_public_key: "node3",
          last_public_key: "node3",
          ip: {127, 0, 0, 1},
          port: 3002
        }
      ]

      Enum.each(nodes, &P2P.add_and_connect_node/1)

      MockClient
      |> stub(:send_message, fn
        %Node{port: 3000}, %GetTransactionChain{address: _}, _ ->
          {:ok, %TransactionList{}}

        %Node{port: 3001}, %GetTransactionChain{address: _}, _ ->
          {:ok,
           %TransactionList{
             transactions: [
               %Transaction{},
               %Transaction{},
               %Transaction{},
               %Transaction{}
             ],
             more?: false
           }}

        %Node{port: 3002}, %GetTransactionChain{address: _}, _ ->
          {:ok,
           %TransactionList{
             transactions: [
               %Transaction{},
               %Transaction{},
               %Transaction{},
               %Transaction{},
               %Transaction{}
             ],
             more?: false
           }}
      end)

      assert 5 =
               TransactionChain.stream_remotely("Alice1", nodes)
               |> Enum.to_list()
               |> List.first()
               |> length()
    end
  end

  describe "fetch_inputs_remotely/2" do
    test "should get the inputs" do
      nodes = [
        %Node{
          first_public_key: "node1",
          last_public_key: "node1",
          ip: {127, 0, 0, 1},
          port: 3000
        },
        %Node{
          first_public_key: "node2",
          last_public_key: "node2",
          ip: {127, 0, 0, 1},
          port: 3001
        },
        %Node{
          first_public_key: "node3",
          last_public_key: "node3",
          ip: {127, 0, 0, 1},
          port: 3002
        }
      ]

      Enum.each(nodes, &P2P.add_and_connect_node/1)

      MockClient
      |> stub(:send_message, fn _, %GetTransactionInputs{address: _}, _ ->
        {:ok,
         %TransactionInputList{
           inputs: [
             %TransactionInput{
               from: "Alice2",
               amount: 10,
               type: :UCO,
               spent?: false,
               timestamp: DateTime.utc_now()
             }
           ]
         }}
      end)

      assert {:ok, [%TransactionInput{from: "Alice2", amount: 10, type: :UCO}]} =
               TransactionChain.fetch_inputs_remotely("Alice1", nodes, DateTime.utc_now())
    end

    test "should resolve the longest inputs when conflicts" do
      nodes = [
        %Node{
          first_public_key: "node1",
          last_public_key: "node1",
          ip: {127, 0, 0, 1},
          port: 3000
        },
        %Node{
          first_public_key: "node2",
          last_public_key: "node2",
          ip: {127, 0, 0, 1},
          port: 3001
        },
        %Node{
          first_public_key: "node3",
          last_public_key: "node3",
          ip: {127, 0, 0, 1},
          port: 3002
        }
      ]

      Enum.each(nodes, &P2P.add_and_connect_node/1)

      MockClient
      |> stub(:send_message, fn
        %Node{port: 3000}, %GetTransactionInputs{address: _}, _ ->
          {:ok, %TransactionInputList{inputs: []}}

        %Node{port: 3001}, %GetTransactionInputs{address: _}, _ ->
          {:ok,
           %TransactionInputList{
             inputs: [
               %TransactionInput{
                 from: "Alice2",
                 amount: 10,
                 type: :UCO,
                 timestamp: DateTime.utc_now()
               }
             ]
           }}

        %Node{port: 3002}, %GetTransactionInputs{address: _}, _ ->
          {:ok,
           %TransactionInputList{
             inputs: [
               %TransactionInput{
                 from: "Alice2",
                 amount: 10,
                 type: :UCO,
                 timestamp: DateTime.utc_now()
               },
               %TransactionInput{
                 from: "Bob3",
                 amount: 2,
                 type: :UCO,
                 timestamp: DateTime.utc_now()
               }
             ]
           }}
      end)

      assert {:ok, [%TransactionInput{from: "Alice2"}, %TransactionInput{from: "Bob3"}]} =
               TransactionChain.fetch_inputs_remotely("Alice1", nodes, DateTime.utc_now())
    end
  end

  describe "fetch_unspent_outputs_remotely/2" do
    test "should get the utxos" do
      nodes = [
        %Node{
          first_public_key: "node1",
          last_public_key: "node1",
          ip: {127, 0, 0, 1},
          port: 3000
        },
        %Node{
          first_public_key: "node2",
          last_public_key: "node2",
          ip: {127, 0, 0, 1},
          port: 3001
        },
        %Node{
          first_public_key: "node3",
          last_public_key: "node3",
          ip: {127, 0, 0, 1},
          port: 3002
        }
      ]

      Enum.each(nodes, &P2P.add_and_connect_node/1)

      MockClient
      |> stub(:send_message, fn _, %GetUnspentOutputs{address: _}, _ ->
        {:ok,
         %UnspentOutputList{
           unspent_outputs: [%UnspentOutput{from: "Alice2", amount: 10, type: :UCO}]
         }}
      end)

      assert {:ok, [%UnspentOutput{from: "Alice2", amount: 10, type: :UCO}]} =
               TransactionChain.fetch_unspent_outputs_remotely("Alice1", nodes)
    end

    test "should resolve the longest utxos when conflicts" do
      nodes = [
        %Node{
          first_public_key: "node1",
          last_public_key: "node1",
          ip: {127, 0, 0, 1},
          port: 3000
        },
        %Node{
          first_public_key: "node2",
          last_public_key: "node2",
          ip: {127, 0, 0, 1},
          port: 3001
        },
        %Node{
          first_public_key: "node3",
          last_public_key: "node3",
          ip: {127, 0, 0, 1},
          port: 3002
        }
      ]

      Enum.each(nodes, &P2P.add_and_connect_node/1)

      MockClient
      |> stub(:send_message, fn
        %Node{port: 3000}, %GetUnspentOutputs{address: _}, _ ->
          {:ok, %UnspentOutputList{unspent_outputs: []}}

        %Node{port: 3001}, %GetUnspentOutputs{address: _}, _ ->
          {:ok,
           %UnspentOutputList{
             unspent_outputs: [%UnspentOutput{from: "Alice2", amount: 10, type: :UCO}]
           }}

        %Node{port: 3002}, %GetUnspentOutputs{address: _}, _ ->
          {:ok,
           %UnspentOutputList{
             unspent_outputs: [
               %UnspentOutput{from: "Alice2", amount: 10, type: :UCO},
               %UnspentOutput{from: "Bob3", amount: 2, type: :UCO}
             ]
           }}
      end)

      assert {:ok, [%UnspentOutput{from: "Alice2"}, %UnspentOutput{from: "Bob3"}]} =
               TransactionChain.fetch_unspent_outputs_remotely("Alice1", nodes)
    end
  end

  describe "fetch_size_remotely/2" do
    test "should get the transaction chain length" do
      nodes = [
        %Node{
          first_public_key: "node1",
          last_public_key: "node1",
          ip: {127, 0, 0, 1},
          port: 3000
        },
        %Node{
          first_public_key: "node2",
          last_public_key: "node2",
          ip: {127, 0, 0, 1},
          port: 3001
        },
        %Node{
          first_public_key: "node3",
          last_public_key: "node3",
          ip: {127, 0, 0, 1},
          port: 3002
        }
      ]

      Enum.each(nodes, &P2P.add_and_connect_node/1)

      MockClient
      |> stub(:send_message, fn _, %GetTransactionChainLength{address: _}, _ ->
        {:ok, %TransactionChainLength{length: 1}}
      end)

      assert {:ok, 1} = TransactionChain.fetch_size_remotely("Alice1", nodes)
    end

    test "should resolve the longest transaction chain when conflicts" do
      nodes = [
        %Node{
          first_public_key: "node1",
          last_public_key: "node1",
          ip: {127, 0, 0, 1},
          port: 3000
        },
        %Node{
          first_public_key: "node2",
          last_public_key: "node2",
          ip: {127, 0, 0, 1},
          port: 3001
        },
        %Node{
          first_public_key: "node3",
          last_public_key: "node3",
          ip: {127, 0, 0, 1},
          port: 3002
        }
      ]

      Enum.each(nodes, &P2P.add_and_connect_node/1)

      MockClient
      |> stub(:send_message, fn
        %Node{port: 3000}, %GetTransactionChainLength{address: _}, _ ->
          {:ok, %TransactionChainLength{length: 1}}

        %Node{port: 3001}, %GetTransactionChainLength{address: _}, _ ->
          {:ok, %TransactionChainLength{length: 2}}

        %Node{port: 3002}, %GetTransactionChainLength{address: _}, _ ->
          {:ok, %TransactionChainLength{length: 1}}
      end)

      assert {:ok, 2} = TransactionChain.fetch_size_remotely("Alice1", nodes)
    end
  end
end
