defmodule Archethic.Contracts.Interpreter.Library.Common.TimeTest do
  @moduledoc """
  Here we test the module within the action block. Because there is AST modification (such as keywords to maps)
  in the ActionInterpreter and we want to test the whole thing.
  """

  use ArchethicCase
  import ArchethicCase

  alias Archethic.Contracts.Interpreter.Library.Common.Time

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData

  doctest Time

  # ----------------------------------------
  describe "now/0" do
    test "should work" do
      now = DateTime.to_unix(DateTime.utc_now())

      code = ~s"""
      actions triggered_by: transaction do
        now = Time.now()
        Contract.set_content now
      end
      """

      assert %Transaction{data: %TransactionData{content: timestamp}} =
               sanitize_parse_execute(code)

      # we validate the test if now is approximately now
      assert String.to_integer(timestamp) - now < 10
    end
  end
end
