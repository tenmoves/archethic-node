defmodule UnirisValidation do
  @moduledoc """
  Uniris Validation workflow using atomic commitment to support the ARCH consensus.

  This module represents each transaction validation in the system and is responsible to
  orchestrate the state holding for the job processed (Context building, Node movements, Ledger movements)
  """

  alias UnirisChain.Transaction
  alias UnirisChain.Transaction.ValidationStamp

  @behaviour __MODULE__.Impl

  @doc """
  Initiate the validation workflow for the given transaction.

  A new process is spawn responsible to gather context and forward information to other validation nodes.

  If the node is the coordinator, it will run the proof of work and manage the acknowledgements of jobs coming from the cross validation nodes. 
  """
  @impl true
  @spec start_validation(Transaction.pending(), UnirisCrypto.key(), list(UnirisCrypto.key())) ::
          {:ok, pid()}
  def start_validation(tx = %Transaction{}, welcome_node_public_key, validation_node_public_keys) do
    impl().start_validation(tx, welcome_node_public_key, validation_node_public_keys)
  end

  @doc """
  Cross validate the stamp coming from a coordinator and return a signature with or without a list of inconsistencies.
  """
  @impl true
  @spec cross_validate(binary(), ValidationStamp.t()) ::
          {signature :: binary(), inconsistencies :: list(atom())}
  def cross_validate(tx_address, stamp = %ValidationStamp{}) do
    impl().cross_validate(tx_address, stamp)
  end

  @doc """
  Add a cross validation coming from other validation node to the transaction processor.

  It includes the signature of the cross validation stamp, the list of inconsistencies and theS
  node emitter of the validation
  """
  @impl true
  @spec add_cross_validation_stamp(
          tx_address :: binary(),
          stamp :: {signature :: binary(), inconsistencies :: list(atom)},
          validation_node :: UnirisCrypto.key()
        ) :: :ok
  def add_cross_validation_stamp(tx_address, stamp = {_sig, _inconsistencies}, validation_node) do
    impl().add_cross_validation_stamp(tx_address, stamp, validation_node)
  end

  @doc """
  Add a context built from a validation node to the transaction processor.

  Context view include the previous storage used to rebuilt the context and view of the availability
  from the elected validation nodes and the next storage pool.
  """
  @impl true
  @spec add_context(
          tx_address :: binary(),
          validation_node_public_key :: UnirisCrypto.key(),
          previous_storage_node_public_keys :: list(UnirisCrypto.key()),
          validation_node_views :: bitstring(),
          storage_node_views :: bitstring()
        ) :: :ok
  def add_context(
        tx_address,
        validation_node_public_key,
        previous_storage_node_public_keys,
        validation_node_views,
        storage_node_views
      ) do
    impl().add_context(
      tx_address,
      validation_node_public_key,
      previous_storage_node_public_keys,
      validation_node_views,
      storage_node_views
    )
  end

  @doc """
  Verify a transaction by download it previous chain and make all the necessary checks:
  - Pending transaction integrity
  - Ledger movements
  - Node movements
  - Atomic commitment
  - Chain integrity

  If the transaction does not match any of these checks, the transaction will be stored as KO
  If the transaction is invalid and if the atomic commitment approved it alo, the transaction will be stored as KO

  Otherwise the transaction will be stored on the TransactionChain
  """
  @impl true
  @spec replicate_transaction(Transaction.validated()) ::
          :ok | {:error, :invalid_transaction} | {:error, :invalid_transaction_chain}
  def replicate_transaction(tx = %Transaction{}) do
    impl().replicate_transaction(tx)
  end

  @doc """
  Determines if the transaction address is under mining
  """
  @impl true
  @spec mining?(binary()) :: boolean()
  def mining?(tx_address) do
    impl().mining?(tx_address)
  end

  @doc """
  Retrieve the mined transaction from an address
  """
  @impl true
  @spec mined_transaction(binary()) :: Transaction.pending()
  def mined_transaction(tx_address) do
    impl().mined_transaction(tx_address)
  end

  defp impl() do
    Application.get_env(:uniris_validation, :impl, __MODULE__.DefaultImpl)
  end
end
