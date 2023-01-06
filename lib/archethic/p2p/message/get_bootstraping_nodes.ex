defmodule Archethic.P2P.Message.GetBootstrappingNodes do
  @moduledoc """
  Represents a message to list the new bootstrapping nodes for a network patch.
  The closest authorized nodes will be returned.

  This message is used during the node bootstrapping.
  """

  alias Archethic.P2P
  alias Archethic.P2P.Message.BootstrappingNodes
  alias Archethic.Crypto

  @enforce_keys [:patch]
  defstruct [:patch]

  @type t() :: %__MODULE__{
          patch: binary()
        }

  @spec encode(t()) :: bitstring()
  def encode(%__MODULE__{patch: patch}) do
    <<0::8, patch::binary-size(3)>>
  end

  @spec process(__MODULE__.t(), Crypto.key()) :: BootstrappingNodes.t()
  def process(%__MODULE__{patch: patch}, _) do
    top_nodes = P2P.authorized_and_available_nodes()

    closest_nodes =
      top_nodes
      |> P2P.nearest_nodes(patch)
      |> Enum.take(5)

    %BootstrappingNodes{
      new_seeds: Enum.take_random(top_nodes, 5),
      closest_nodes: closest_nodes
    }
  end
end
