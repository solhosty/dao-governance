"use client";

import { useMemo, useState } from "react";
import { formatEther, parseEther } from "viem";
import {
  useAccount,
  usePublicClient,
  useReadContract,
  useWaitForTransactionReceipt,
  useWriteContract,
} from "wagmi";

import { daoTokenMarketAbi } from "@/lib/abi/daoTokenMarket";

type BuyTokenFormProps = {
  marketAddress: `0x${string}`;
  tokenSymbol?: string;
};

type TradeTab = "buy" | "sell";

function parseTokenAmount(input: string): bigint {
  const trimmed = input.trim();
  if (!/^\d+$/.test(trimmed)) {
    return 0n;
  }

  try {
    return BigInt(trimmed);
  } catch {
    return 0n;
  }
}

function parseSlippageBps(input: string): bigint {
  const parsed = Number.parseFloat(input);
  if (!Number.isFinite(parsed) || parsed < 0) {
    return 0n;
  }

  const bounded = Math.min(parsed, 100);
  return BigInt(Math.floor(bounded * 100));
}

export function BuyTokenForm({ marketAddress, tokenSymbol = "TOKEN" }: BuyTokenFormProps) {
  const [tab, setTab] = useState<TradeTab>("buy");
  const [ethAmount, setEthAmount] = useState("0.1");
  const [sellTokenAmount, setSellTokenAmount] = useState("1");
  const [slippage, setSlippage] = useState("1");
  const [txError, setTxError] = useState<string | null>(null);

  const { address: account } = useAccount();
  const publicClient = usePublicClient();

  const buyAmountWei = useMemo(() => {
    try {
      return parseEther(ethAmount);
    } catch {
      return 0n;
    }
  }, [ethAmount]);

  const sellAmount = useMemo(() => parseTokenAmount(sellTokenAmount), [sellTokenAmount]);
  const slippageBps = useMemo(() => parseSlippageBps(slippage), [slippage]);

  const {
    data: buyQuote,
    error: buyQuoteError,
    isLoading: isBuyQuoteLoading,
  } = useReadContract({
    abi: daoTokenMarketAbi,
    address: marketAddress,
    functionName: "quoteBuy",
    args: [buyAmountWei],
    query: { enabled: buyAmountWei > 0n },
  });

  const {
    data: sellQuote,
    error: sellQuoteError,
    isLoading: isSellQuoteLoading,
  } = useReadContract({
    abi: daoTokenMarketAbi,
    address: marketAddress,
    functionName: "quoteSell",
    args: [sellAmount],
    query: { enabled: sellAmount > 0n },
  });

  const { data: hash, isPending, writeContractAsync } = useWriteContract();
  const { isLoading: isConfirming } = useWaitForTransactionReceipt({ hash });

  const buyMinTokensOut = useMemo(() => {
    if (!buyQuote) return 0n;
    return (buyQuote * (10_000n - slippageBps)) / 10_000n;
  }, [buyQuote, slippageBps]);

  const sellMinEthOut = useMemo(() => {
    if (!sellQuote) return 0n;
    return (sellQuote * (10_000n - slippageBps)) / 10_000n;
  }, [sellQuote, slippageBps]);

  const isBusy = isPending || isConfirming;

  const executeBuy = async () => {
    if (!account || !publicClient || buyAmountWei === 0n || buyMinTokensOut === 0n) {
      return;
    }

    setTxError(null);

    let gas = 500_000n;
    try {
      gas = await publicClient.estimateContractGas({
        account,
        abi: daoTokenMarketAbi,
        address: marketAddress,
        functionName: "buy",
        args: [buyMinTokensOut],
        value: buyAmountWei,
      });
    } catch {
      gas = 500_000n;
    }

    try {
      await writeContractAsync({
        abi: daoTokenMarketAbi,
        address: marketAddress,
        functionName: "buy",
        args: [buyMinTokensOut],
        value: buyAmountWei,
        gas,
      });
    } catch (error) {
      setTxError(error instanceof Error ? error.message : "Transaction failed");
    }
  };

  const executeSell = async () => {
    if (!account || !publicClient || sellAmount === 0n || sellMinEthOut === 0n) {
      return;
    }

    setTxError(null);

    let gas = 500_000n;
    try {
      gas = await publicClient.estimateContractGas({
        account,
        abi: daoTokenMarketAbi,
        address: marketAddress,
        functionName: "sell",
        args: [sellAmount, sellMinEthOut],
      });
    } catch {
      gas = 500_000n;
    }

    try {
      await writeContractAsync({
        abi: daoTokenMarketAbi,
        address: marketAddress,
        functionName: "sell",
        args: [sellAmount, sellMinEthOut],
        gas,
      });
    } catch (error) {
      setTxError(error instanceof Error ? error.message : "Transaction failed");
    }
  };

  return (
    <div className="rounded-lg border border-white/40 bg-white/60 p-4 shadow-glass backdrop-blur-md">
      <div className="mb-3 flex items-center justify-between gap-2">
        <h3 className="text-lg font-semibold">Trade Tokens</h3>
        <div className="rounded-md border border-slate-300 bg-white p-1">
          <button
            className={`rounded px-2 py-1 text-xs font-medium ${
              tab === "buy" ? "bg-slate-900 text-white" : "text-slate-700"
            }`}
            onClick={() => setTab("buy")}
            type="button"
          >
            Buy
          </button>
          <button
            className={`rounded px-2 py-1 text-xs font-medium ${
              tab === "sell" ? "bg-slate-900 text-white" : "text-slate-700"
            }`}
            onClick={() => setTab("sell")}
            type="button"
          >
            Sell
          </button>
        </div>
      </div>
      <div className="grid gap-3">
        {tab === "buy" ? (
          <>
            <input
              className="rounded-md border border-slate-300 bg-white px-3 py-2 text-sm"
              value={ethAmount}
              onChange={(event) => setEthAmount(event.target.value)}
              placeholder="ETH amount"
            />
            <p className="text-xs text-slate-500">
              Expected output: {isBuyQuoteLoading ? "Loading..." : String(buyQuote ?? 0n)} {tokenSymbol}
            </p>
            <p className="text-xs text-slate-500">
              Minimum output after slippage: {String(buyMinTokensOut)} {tokenSymbol}
            </p>
          </>
        ) : (
          <>
            <input
              className="rounded-md border border-slate-300 bg-white px-3 py-2 text-sm"
              value={sellTokenAmount}
              onChange={(event) => setSellTokenAmount(event.target.value)}
              placeholder={`${tokenSymbol} amount`}
            />
            <p className="text-xs text-slate-500">
              Estimated ETH out: {isSellQuoteLoading ? "Loading..." : formatEther(sellQuote ?? 0n)} ETH
            </p>
            <p className="text-xs text-slate-500">
              Minimum ETH out after slippage: {formatEther(sellMinEthOut)} ETH
            </p>
          </>
        )}
        <input
          className="rounded-md border border-slate-300 bg-white px-3 py-2 text-sm"
          value={slippage}
          onChange={(event) => setSlippage(event.target.value)}
          placeholder="Slippage %"
        />
        <button
          className="rounded-md bg-slate-900 px-4 py-2 text-sm text-white disabled:opacity-60"
          disabled={
            isBusy ||
            !account ||
            (tab === "buy" ? buyAmountWei === 0n || buyMinTokensOut === 0n : sellAmount === 0n || sellMinEthOut === 0n)
          }
          onClick={tab === "buy" ? executeBuy : executeSell}
        >
          {isBusy ? "Submitting..." : tab === "buy" ? "Buy" : "Sell"}
        </button>
        {!account ? <p className="text-xs text-amber-700">Connect wallet to trade</p> : null}
        {tab === "buy" && buyQuoteError ? <p className="text-xs text-red-600">Quote error: {buyQuoteError.message}</p> : null}
        {tab === "sell" && sellQuoteError ? <p className="text-xs text-red-600">Quote error: {sellQuoteError.message}</p> : null}
        {txError ? <p className="text-xs text-red-600">Transaction error: {txError}</p> : null}
        {hash ? <p className="text-xs text-slate-500">Tx: {hash}</p> : null}
      </div>
    </div>
  );
}
