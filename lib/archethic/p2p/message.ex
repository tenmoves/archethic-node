defmodule Archethic.P2P.Message do
  @moduledoc """
  Provide functions to encode and decode P2P messages using a custom binary protocol
  """

  alias Archethic.{
    Crypto,
    P2P.Node,
    Utils,
    Utils.VarInt
  }

  alias Archethic.BeaconChain.{
    ReplicationAttestation,
    Summary,
    SummaryAggregate,
    Slot,
    Slot
  }

  alias Archethic.TransactionChain.{
    Transaction,
    Transaction.CrossValidationStamp,
    Transaction.ValidationStamp,
    TransactionSummary,
    VersionedTransactionInput,
    Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput
  }

  alias __MODULE__.{
    AcknowledgeStorage,
    AddMiningContext,
    AddressList,
    Balance,
    BeaconSummaryList,
    BeaconUpdate,
    BootstrappingNodes,
    CrossValidate,
    CrossValidationDone,
    EncryptedStorageNonce,
    Error,
    FirstPublicKey,
    GenesisAddress,
    GetGenesisAddress,
    GetBalance,
    GetBeaconSummaries,
    GetBeaconSummary,
    GetBeaconSummariesAggregate,
    GetBootstrappingNodes,
    GetCurrentSummaries,
    GetFirstPublicKey,
    GetLastTransaction,
    GetLastTransactionAddress,
    GetNextAddresses,
    GetP2PView,
    GetStorageNonce,
    GetTransaction,
    GetTransactionChain,
    GetTransactionChainLength,
    GetTransactionInputs,
    GetTransactionSummary,
    GetUnspentOutputs,
    LastTransactionAddress,
    ListNodes,
    NewBeaconSlot,
    NewTransaction,
    NodeList,
    NotFound,
    NotifyEndOfNodeSync,
    NotifyLastTransactionAddress,
    NotifyPreviousChain,
    Ok,
    P2PView,
    Ping,
    RegisterBeaconUpdates,
    ReplicateTransaction,
    ReplicateTransactionChain,
    ReplicationError,
    ShardRepair,
    StartMining,
    TransactionChainLength,
    TransactionInputList,
    TransactionSummaryList,
    TransactionList,
    UnspentOutputList,
    ValidationError,
    ValidateTransaction,
    ReplicatePendingTransactionChain,
    NotifyReplicationValidation
  }

  require Logger

  @type t :: request() | response()

  @type request ::
          GetBootstrappingNodes.t()
          | GetStorageNonce.t()
          | ListNodes.t()
          | GetTransaction.t()
          | GetTransactionChain.t()
          | GetUnspentOutputs.t()
          | GetP2PView.t()
          | NewTransaction.t()
          | StartMining.t()
          | AddMiningContext.t()
          | CrossValidate.t()
          | CrossValidationDone.t()
          | ReplicateTransaction.t()
          | ReplicateTransactionChain.t()
          | GetLastTransaction.t()
          | GetBalance.t()
          | GetTransactionInputs.t()
          | GetTransactionChainLength.t()
          | NotifyEndOfNodeSync.t()
          | GetLastTransactionAddress.t()
          | NotifyLastTransactionAddress.t()
          | Ping.t()
          | GetBeaconSummary.t()
          | NewBeaconSlot.t()
          | GetBeaconSummaries.t()
          | RegisterBeaconUpdates.t()
          | BeaconUpdate.t()
          | TransactionSummary.t()
          | ReplicationAttestation.t()
          | GetGenesisAddress.t()
          | ValidationError.t()
          | GetCurrentSummaries.t()
          | GetBeaconSummariesAggregate.t()
          | NotifyPreviousChain.t()
          | ShardRepair.t()
          | GetNextAddresses.t()
          | ValidateTransaction.t()
          | ReplicatePendingTransactionChain.t()
          | NotifyReplicationValidation.t()

  @type response ::
          Ok.t()
          | NotFound.t()
          | TransactionList.t()
          | Transaction.t()
          | NodeList.t()
          | UnspentOutputList.t()
          | Balance.t()
          | EncryptedStorageNonce.t()
          | BootstrappingNodes.t()
          | P2PView.t()
          | TransactionSummary.t()
          | LastTransactionAddress.t()
          | FirstPublicKey.t()
          | TransactionChainLength.t()
          | TransactionInputList.t()
          | TransactionSummaryList.t()
          | Error.t()
          | Summary.t()
          | BeaconSummaryList.t()
          | GenesisAddress.t()
          | ReplicationError.t()
          | SummaryAggregate.t()
          | AddressList.t()

  @floor_upload_speed Application.compile_env!(:archethic, [__MODULE__, :floor_upload_speed])
  @content_max_size Application.compile_env!(:archethic, :transaction_data_content_max_size)

  @doc """
  Extract the Message Struct name
  """
  @spec name(t()) :: String.t()
  def name(message) when is_struct(message) do
    message.__struct__
    |> Module.split()
    |> List.last()
  end

  @doc """
  Return timeout depending of message type
  """
  @spec get_timeout(__MODULE__.t()) :: non_neg_integer()
  def get_timeout(%GetTransaction{}), do: get_max_timeout()
  def get_timeout(%GetLastTransaction{}), do: get_max_timeout()
  def get_timeout(%NewTransaction{}), do: get_max_timeout()
  def get_timeout(%StartMining{}), do: get_max_timeout()
  def get_timeout(%ReplicateTransaction{}), do: get_max_timeout()
  def get_timeout(%ReplicateTransactionChain{}), do: get_max_timeout()
  def get_timeout(%ValidateTransaction{}), do: get_max_timeout()

  def get_timeout(%GetTransactionChain{}) do
    # As we use 10 transaction in the pagination we can estimate the max time
    get_max_timeout() * 10
  end

  #  def get_timeout(%GetBeaconSummaries{addresses: addresses}) do
  #    # We can expect high beacon summary where a transaction replication will contains a single UCO transfer
  #    # CALC: Tx address +  recipient address + tx type + tx timestamp + storage node public key + signature * 200 (max storage nodes)
  #    beacon_summary_high_estimation_bytes = 34 + 34 + 1 + 8 + (8 + 34 + 34 * 200)
  #    length(addresses) * trunc(beacon_summary_high_estimation_bytes / @floor_upload_speed * 1000)
  #  end

  def get_timeout(_), do: 3_000

  @doc """
  Return the maximum timeout for a full sized transaction
  """
  @spec get_max_timeout() :: non_neg_integer()
  def get_max_timeout() do
    trunc(@content_max_size / @floor_upload_speed * 1_000)
  end

  @doc """
  Serialize a message into binary

  ## Examples

      iex> Message.encode(%Ok{})
      <<254>>

      iex> %Message.GetTransaction{
      ...>  address: <<0, 40, 71, 99, 6, 218, 243, 156, 193, 63, 176, 168, 22, 226, 31, 170, 119, 122,
      ...>    13, 188, 75, 49, 171, 219, 222, 133, 86, 132, 188, 206, 233, 66, 7>>
      ...> } |> Message.encode()
      <<
      # Message type
      3,
      # Address
      0, 40, 71, 99, 6, 218, 243, 156, 193, 63, 176, 168, 22, 226, 31, 170, 119, 122,
      13, 188, 75, 49, 171, 219, 222, 133, 86, 132, 188, 206, 233, 66, 7
      >>
  """
  @spec encode(t()) :: bitstring()
  def encode(msg), do: msg.__struct__.encode(msg)

  @doc """
  Decode an encoded message
  """
  @spec decode(bitstring()) :: {t(), bitstring}
  def decode(<<0::8, patch::binary-size(3), rest::bitstring>>) do
    {
      %GetBootstrappingNodes{patch: patch},
      rest
    }
  end

  def decode(<<1::8, rest::bitstring>>) do
    {public_key, rest} = Utils.deserialize_public_key(rest)

    {
      %GetStorageNonce{
        public_key: public_key
      },
      rest
    }
  end

  def decode(<<2::8, rest::bitstring>>) do
    {%ListNodes{}, rest}
  end

  def decode(<<3::8, rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)

    {
      %GetTransaction{address: address},
      rest
    }
  end

  #
  def decode(<<4::8, rest::bitstring>>) do
    {address,
     <<order_bit::1, paging_state_size::8, paging_state::binary-size(paging_state_size),
       rest::bitstring>>} = Utils.deserialize_address(rest)

    paging_state =
      case paging_state do
        "" ->
          nil

        _ ->
          paging_state
      end

    order =
      case order_bit do
        0 -> :asc
        1 -> :desc
      end

    {
      %GetTransactionChain{address: address, paging_state: paging_state, order: order},
      rest
    }
  end

  def decode(<<5::8, rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)

    {offset, rest} = VarInt.get_value(rest)
    {%GetUnspentOutputs{address: address, offset: offset}, rest}
  end

  def decode(<<6::8, rest::bitstring>>) do
    {tx, rest} = Transaction.deserialize(rest)
    {%NewTransaction{transaction: tx}, rest}
  end

  def decode(<<7::8, rest::bitstring>>) do
    {tx, rest} = Transaction.deserialize(rest)

    {welcome_node_public_key, <<nb_validation_nodes::8, rest::bitstring>>} =
      Utils.deserialize_public_key(rest)

    {validation_node_public_keys, rest} =
      Utils.deserialize_public_key_list(rest, nb_validation_nodes, [])

    {%StartMining{
       transaction: tx,
       welcome_node_public_key: welcome_node_public_key,
       validation_node_public_keys: validation_node_public_keys
     }, rest}
  end

  def decode(<<8::8, rest::bitstring>>) do
    {tx_address, rest} = Utils.deserialize_address(rest)

    {node_public_key, <<nb_previous_storage_nodes::8, rest::bitstring>>} =
      Utils.deserialize_public_key(rest)

    {previous_storage_nodes_keys, rest} =
      Utils.deserialize_public_key_list(rest, nb_previous_storage_nodes, [])

    <<
      chain_storage_nodes_view_size::8,
      chain_storage_nodes_view::bitstring-size(chain_storage_nodes_view_size),
      beacon_storage_nodes_view_size::8,
      beacon_storage_nodes_view::bitstring-size(beacon_storage_nodes_view_size),
      io_storage_nodes_view_size::8,
      io_storage_nodes_view::bitstring-size(io_storage_nodes_view_size),
      rest::bitstring
    >> = rest

    {%AddMiningContext{
       address: tx_address,
       validation_node_public_key: node_public_key,
       chain_storage_nodes_view: chain_storage_nodes_view,
       beacon_storage_nodes_view: beacon_storage_nodes_view,
       io_storage_nodes_view: io_storage_nodes_view,
       previous_storage_nodes_public_keys: previous_storage_nodes_keys
     }, rest}
  end

  def decode(<<9::8, rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)
    {validation_stamp, <<nb_validations::8, rest::bitstring>>} = ValidationStamp.deserialize(rest)

    <<chain_tree_size::8, rest::bitstring>> = rest

    {chain_tree, <<beacon_tree_size::8, rest::bitstring>>} =
      deserialize_bit_sequences(rest, nb_validations, chain_tree_size, [])

    {beacon_tree, <<io_tree_size::8, rest::bitstring>>} =
      deserialize_bit_sequences(rest, nb_validations, beacon_tree_size, [])

    {io_tree, rest} =
      if io_tree_size > 0 do
        deserialize_bit_sequences(rest, nb_validations, io_tree_size, [])
      else
        {[], rest}
      end

    <<nb_cross_validation_nodes::8,
      cross_validation_node_confirmation::bitstring-size(nb_cross_validation_nodes),
      rest::bitstring>> = rest

    {%CrossValidate{
       address: address,
       validation_stamp: validation_stamp,
       replication_tree: %{
         chain: chain_tree,
         beacon: beacon_tree,
         IO: io_tree
       },
       confirmed_validation_nodes: cross_validation_node_confirmation
     }, rest}
  end

  def decode(<<10::8, rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)
    {stamp, rest} = CrossValidationStamp.deserialize(rest)

    {%CrossValidationDone{
       address: address,
       cross_validation_stamp: stamp
     }, rest}
  end

  def decode(<<11::8, rest::bitstring>>) do
    {tx, <<replying_node::1, rest::bitstring>>} = Transaction.deserialize(rest)

    if replying_node == 1 do
      {node_public_key, rest} = Utils.deserialize_public_key(rest)

      {%ReplicateTransactionChain{
         transaction: tx,
         replying_node: node_public_key
       }, rest}
    else
      {%ReplicateTransactionChain{
         transaction: tx
       }, rest}
    end
  end

  def decode(<<12::8, rest::bitstring>>) do
    {tx, rest} = Transaction.deserialize(rest)

    {%ReplicateTransaction{
       transaction: tx
     }, rest}
  end

  def decode(<<13::8, rest::bitstring>>) do
    {address, <<signature_size::8, signature::binary-size(signature_size), rest::bitstring>>} =
      Utils.deserialize_address(rest)

    {%AcknowledgeStorage{
       address: address,
       signature: signature
     }, rest}
  end

  def decode(<<14::8, rest::bitstring>>) do
    {public_key, <<timestamp::32, rest::bitstring>>} = Utils.deserialize_public_key(rest)

    {%NotifyEndOfNodeSync{
       node_public_key: public_key,
       timestamp: DateTime.from_unix!(timestamp)
     }, rest}
  end

  def decode(<<15::8, rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)
    {%GetLastTransaction{address: address}, rest}
  end

  def decode(<<16::8, rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)
    {%GetBalance{address: address}, rest}
  end

  def decode(<<17::8, rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)
    {offset, rest} = VarInt.get_value(rest)
    {limit, rest} = VarInt.get_value(rest)
    {%GetTransactionInputs{address: address, offset: offset, limit: limit}, rest}
  end

  def decode(<<18::8, rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)
    {%GetTransactionChainLength{address: address}, rest}
  end

  def decode(<<19::8, rest::bitstring>>) do
    {nb_node_public_keys, rest} = rest |> VarInt.get_value()
    {public_keys, rest} = Utils.deserialize_public_key_list(rest, nb_node_public_keys, [])
    {%GetP2PView{node_public_keys: public_keys}, rest}
  end

  def decode(<<20::8, rest::bitstring>>) do
    {public_key, rest} = Utils.deserialize_public_key(rest)

    {%GetFirstPublicKey{
       public_key: public_key
     }, rest}
  end

  def decode(<<21::8, rest::bitstring>>) do
    {address, <<timestamp::64, rest::bitstring>>} = Utils.deserialize_address(rest)

    {%GetLastTransactionAddress{
       address: address,
       timestamp: DateTime.from_unix!(timestamp, :millisecond)
     }, rest}
  end

  def decode(<<22::8, rest::bitstring>>) do
    {last_address, rest} = Utils.deserialize_address(rest)
    {genesis_address, rest} = Utils.deserialize_address(rest)
    {previous_address, <<timestamp::64, rest::bitstring>>} = Utils.deserialize_address(rest)

    {%NotifyLastTransactionAddress{
       last_address: last_address,
       genesis_address: genesis_address,
       previous_address: previous_address,
       timestamp: DateTime.from_unix!(timestamp, :millisecond)
     }, rest}
  end

  def decode(<<23::8, rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)
    {%GetTransactionSummary{address: address}, rest}
  end

  def decode(<<25::8, rest::binary>>), do: {%Ping{}, rest}

  def decode(<<26::8, rest::binary>>) do
    {address, rest} = Utils.deserialize_address(rest)

    {
      %GetBeaconSummary{address: address},
      rest
    }
  end

  def decode(<<27::8, rest::bitstring>>) do
    {slot = %Slot{}, rest} = Slot.deserialize(rest)

    {
      %NewBeaconSlot{slot: slot},
      rest
    }
  end

  def decode(<<28::8, rest::bitstring>>) do
    {nb_addresses, rest} = rest |> VarInt.get_value()
    {addresses, rest} = Utils.deserialize_addresses(rest, nb_addresses, [])

    {
      %GetBeaconSummaries{addresses: addresses},
      rest
    }
  end

  def decode(<<29::8, subset::binary-size(1), rest::binary>>) do
    {public_key, rest} = Utils.deserialize_public_key(rest)

    {
      %RegisterBeaconUpdates{
        subset: subset,
        node_public_key: public_key
      },
      rest
    }
  end

  def decode(<<30::8, rest::bitstring>>) do
    ReplicationAttestation.deserialize(rest)
  end

  def decode(<<31::8, rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)
    {%GetGenesisAddress{address: address}, rest}
  end

  def decode(<<32::8, nb_subsets::8, rest::binary>>) do
    subsets_bin = :binary.part(rest, 0, nb_subsets)
    subsets = for <<subset::8 <- subsets_bin>>, do: <<subset>>
    {%GetCurrentSummaries{subsets: subsets}, <<>>}
  end

  def decode(<<33::8, timestamp::32, rest::bitstring>>) do
    {%GetBeaconSummariesAggregate{date: DateTime.from_unix!(timestamp)}, rest}
  end

  def decode(<<34::8, rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)
    {%NotifyPreviousChain{address: address}, rest}
  end

  def decode(<<35::8, rest::bitstring>>) do
    GetNextAddresses.deserialize(rest)
  end

  def decode(<<36::8, rest::bitstring>>) do
    ValidateTransaction.deserialize(rest)
  end

  def decode(<<37::8, rest::bitstring>>) do
    ReplicatePendingTransactionChain.deserialize(rest)
  end

  def decode(<<38::8, rest::bitstring>>) do
    NotifyReplicationValidation.deserialize(rest)
  end

  def decode(<<229::8, rest::bitstring>>) do
    AddressList.deserialize(rest)
  end

  def decode(<<230::8, rest::bitstring>>) do
    ShardRepair.deserialize(rest)
  end

  def decode(<<231::8, rest::bitstring>>) do
    SummaryAggregate.deserialize(rest)
  end

  def decode(<<232::8, rest::bitstring>>) do
    {nb_transaction_summaries, rest} = rest |> VarInt.get_value()

    {transaction_summaries, rest} =
      Utils.deserialize_transaction_summaries(rest, nb_transaction_summaries, [])

    {
      %TransactionSummaryList{
        transaction_summaries: transaction_summaries
      },
      rest
    }
  end

  def decode(<<233::8, rest::bitstring>>) do
    ReplicationError.deserialize(rest)
  end

  def decode(<<234::8, rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)

    {reason_size, rest} = VarInt.get_value(rest)

    case rest do
      <<reason::binary-size(reason_size), 0::8, rest::bitstring>> ->
        {%ValidationError{reason: reason, context: :network_issue, address: address}, rest}

      <<reason::binary-size(reason_size), 1::8, rest::bitstring>> ->
        {%ValidationError{reason: reason, context: :invalid_transaction, address: address}, rest}
    end
  end

  def decode(<<235::8, rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)
    {%GenesisAddress{address: address}, rest}
  end

  def decode(<<236::8, rest::bitstring>>) do
    {nb_transaction_attestations, rest} = rest |> VarInt.get_value()

    {transaction_attestations, rest} =
      Utils.deserialize_transaction_attestations(rest, nb_transaction_attestations, [])

    {
      %BeaconUpdate{
        transaction_attestations: transaction_attestations
      },
      rest
    }
  end

  def decode(<<237::8, rest::bitstring>>) do
    {nb_summaries, rest} = rest |> VarInt.get_value()
    {summaries, rest} = deserialize_summaries(rest, nb_summaries, [])

    {
      %BeaconSummaryList{summaries: summaries},
      rest
    }
  end

  def decode(<<238::8, reason::8, rest::bitstring>>) do
    {%Error{reason: Error.deserialize_reason(reason)}, rest}
  end

  def decode(<<239::8, rest::bitstring>>) do
    TransactionSummary.deserialize(rest)
  end

  def decode(<<240::8, rest::bitstring>>) do
    Summary.deserialize(rest)
  end

  def decode(<<241::8, rest::bitstring>>) do
    {address, <<timestamp::64, rest::bitstring>>} = Utils.deserialize_address(rest)

    {%LastTransactionAddress{
       address: address,
       timestamp: DateTime.from_unix!(timestamp, :millisecond)
     }, rest}
  end

  def decode(<<242::8, rest::bitstring>>) do
    {public_key, rest} = Utils.deserialize_public_key(rest)
    {%FirstPublicKey{public_key: public_key}, rest}
  end

  def decode(<<243::8, view_size::8, rest::bitstring>>) do
    <<nodes_view::bitstring-size(view_size), rest::bitstring>> = rest
    {%P2PView{nodes_view: nodes_view}, rest}
  end

  def decode(<<244::8, rest::bitstring>>) do
    {nb_inputs, rest} = rest |> VarInt.get_value()

    {inputs, <<more_bit::1, rest::bitstring>>} =
      deserialize_versioned_transaction_inputs(rest, nb_inputs, [])

    more? = more_bit == 1

    {offset, rest} = VarInt.get_value(rest)

    {%TransactionInputList{
       inputs: inputs,
       more?: more?,
       offset: offset
     }, rest}
  end

  def decode(<<245::8, rest::bitstring>>) do
    {length, rest} = rest |> VarInt.get_value()

    {%TransactionChainLength{
       length: length
     }, rest}
  end

  def decode(<<246::8, rest::bitstring>>) do
    {nb_new_seeds, rest} = rest |> VarInt.get_value()
    {new_seeds, <<rest::bitstring>>} = deserialize_node_list(rest, nb_new_seeds, [])

    {nb_closest_nodes, rest} = rest |> VarInt.get_value()
    {closest_nodes, rest} = deserialize_node_list(rest, nb_closest_nodes, [])

    {%BootstrappingNodes{
       new_seeds: new_seeds,
       closest_nodes: closest_nodes
     }, rest}
  end

  def decode(<<247::8, digest_size::8, digest::binary-size(digest_size), rest::bitstring>>) do
    {%EncryptedStorageNonce{
       digest: digest
     }, rest}
  end

  def decode(<<248::8, uco_balance::64, rest::bitstring>>) do
    {nb_token_balances, rest} = rest |> VarInt.get_value()
    {token_balances, rest} = deserialize_token_balances(rest, nb_token_balances, %{})

    {%Balance{
       uco: uco_balance,
       token: token_balances
     }, rest}
  end

  def decode(<<249::8, rest::bitstring>>) do
    {nb_nodes, rest} = rest |> VarInt.get_value()
    {nodes, rest} = deserialize_node_list(rest, nb_nodes, [])
    {%NodeList{nodes: nodes}, rest}
  end

  def decode(<<250::8, rest::bitstring>>) do
    {nb_unspent_outputs, rest} = rest |> VarInt.get_value()

    {unspent_outputs, <<more_bit::1, rest::bitstring>>} =
      deserialize_versioned_unspent_output_list(rest, nb_unspent_outputs, [])

    more? = more_bit == 1

    {offset, rest} = VarInt.get_value(rest)

    {%UnspentOutputList{unspent_outputs: unspent_outputs, more?: more?, offset: offset}, rest}
  end

  def decode(<<251::8, rest::bitstring>>) do
    {nb_transactions, rest} = rest |> VarInt.get_value()
    {transactions, rest} = deserialize_tx_list(rest, nb_transactions, [])

    case rest do
      <<0::1, rest::bitstring>> ->
        {
          %TransactionList{transactions: transactions, more?: false},
          rest
        }

      <<1::1, paging_state_size::8, paging_state::binary-size(paging_state_size),
        rest::bitstring>> ->
        {
          %TransactionList{transactions: transactions, more?: true, paging_state: paging_state},
          rest
        }
    end
  end

  def decode(<<252::8, rest::bitstring>>) do
    Transaction.deserialize(rest)
  end

  def decode(<<253::8, rest::bitstring>>) do
    {%NotFound{}, rest}
  end

  def decode(<<254::8, rest::bitstring>>) do
    {%Ok{}, rest}
  end

  def decode(<<255::8>>), do: raise("255 message type is reserved for stream EOF")

  defp deserialize_node_list(rest, 0, _acc), do: {[], rest}

  defp deserialize_node_list(rest, nb_nodes, acc) when length(acc) == nb_nodes do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_node_list(rest, nb_nodes, acc) do
    {node, rest} = Node.deserialize(rest)
    deserialize_node_list(rest, nb_nodes, [node | acc])
  end

  defp deserialize_tx_list(rest, 0, _acc), do: {[], rest}

  defp deserialize_tx_list(rest, nb_transactions, acc) when length(acc) == nb_transactions do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_tx_list(rest, nb_transactions, acc) do
    {tx, rest} = Transaction.deserialize(rest)
    deserialize_tx_list(rest, nb_transactions, [tx | acc])
  end

  defp deserialize_versioned_unspent_output_list(rest, 0, _acc), do: {[], rest}

  defp deserialize_versioned_unspent_output_list(rest, nb_unspent_outputs, acc)
       when length(acc) == nb_unspent_outputs do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_versioned_unspent_output_list(
         rest,
         nb_unspent_outputs,
         acc
       ) do
    {unspent_output, rest} = VersionedUnspentOutput.deserialize(rest)

    deserialize_versioned_unspent_output_list(rest, nb_unspent_outputs, [unspent_output | acc])
  end

  defp deserialize_versioned_transaction_inputs(rest, 0, _acc), do: {[], rest}

  defp deserialize_versioned_transaction_inputs(rest, nb_inputs, acc)
       when length(acc) == nb_inputs do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_versioned_transaction_inputs(
         rest,
         nb_inputs,
         acc
       ) do
    {input, rest} = VersionedTransactionInput.deserialize(rest)
    deserialize_versioned_transaction_inputs(rest, nb_inputs, [input | acc])
  end

  defp deserialize_token_balances(rest, 0, _acc), do: {%{}, rest}

  defp deserialize_token_balances(rest, token_balances, acc)
       when map_size(acc) == token_balances do
    {acc, rest}
  end

  defp deserialize_token_balances(rest, nb_token_balances, acc) do
    {token_address, <<amount::64, rest::bitstring>>} = Utils.deserialize_address(rest)
    {token_id, rest} = VarInt.get_value(rest)

    deserialize_token_balances(
      rest,
      nb_token_balances,
      Map.put(acc, {token_address, token_id}, amount)
    )
  end

  defp deserialize_summaries(rest, 0, _), do: {[], rest}

  defp deserialize_summaries(rest, nb_summaries, acc) when nb_summaries == length(acc),
    do: {Enum.reverse(acc), rest}

  defp deserialize_summaries(rest, nb_summaries, acc) do
    {summary, rest} = Summary.deserialize(rest)
    deserialize_summaries(rest, nb_summaries, [summary | acc])
  end

  defp deserialize_bit_sequences(rest, nb_sequences, _sequence_size, acc)
       when length(acc) == nb_sequences do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_bit_sequences(rest, nb_sequences, sequence_size, acc) do
    <<sequence::bitstring-size(sequence_size), rest::bitstring>> = rest
    deserialize_bit_sequences(rest, nb_sequences, sequence_size, [sequence | acc])
  end

  @doc """
  Handle a P2P message by processing it and return list of responses to be streamed back to the client
  """
  @spec process(request(), Crypto.key()) :: response()
  def process(msg, key), do: msg.__struct__.process(msg, key)
end
