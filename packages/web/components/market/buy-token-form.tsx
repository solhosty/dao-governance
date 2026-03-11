"use client";

import { useMemo, useState } from "react";
import { formatEther, parseEther } from "viem";
import { useReadContract, useWaitForTransactionReceipt, useWriteContract } from "wagmi";

import { daoTokenMarketAbi } from "@/lib/abi/daoTokenMarket";

type BuyTokenFormProps = {
  marketAddress: `0x${string}`;
};

export function BuyTokenForm({ marketAddress }: BuyTokenFormProps) {
  const [ethAmount, setEthAmount] = useState("0.1");
  const amountWei = useMemo(() => {
    try {
      return parseEther(ethAmount);
    } catch {
      return 0n;
    }
  }, [ethAmount]);

  const { data: quote } = useReadContract({
    abi: daoTokenMarketAbi,
    address: marketAddress,
    functionName: "quoteBuy",
    args: [amountWei],
    query: { enabled: amountWei > 0n },
  });

  const { data: hash, isPending, writeContract } = useWriteContract();
  const { isLoading: isConfirming } = useWaitForTransactionReceipt({ hash });

  return (
    <div className="rounded-lg border border-white/40 bg-white/60 p-4 shadow-glass backdrop-blur-md">
      <h3 className="mb-3 text-lg font-semibold">Buy Tokens</h3>
      <div className="grid gap-3">
        <input
          className="rounded-md border border-slate-300 bg-white px-3 py-2 text-sm"
          value={ethAmount}
          onChange={(event) => setEthAmount(event.target.value)}
          placeholder="ETH amount"
        />
        <p className="text-xs text-slate-500">Expected output: {String(quote ?? 0n)} GOV</p>
        <button
          className="rounded-md bg-slate-900 px-4 py-2 text-sm text-white disabled:opacity-60"
          disabled={amountWei === 0n || isPending || isConfirming}
          onClick={() => {
            writeContract({
              abi: daoTokenMarketAbi,
              address: marketAddress,
              functionName: "buy",
              args: [quote ?? 0n],
              value: amountWei,
            });
          }}
        >
          {isPending || isConfirming ? "Purchasing..." : "Buy"}
        </button>
        {hash ? <p className="text-xs text-slate-500">Tx: {hash}</p> : null}
        {quote ? (
          <p className="text-xs text-slate-500">Quote normalized: {formatEther(quote)} tokens</p>
        ) : null}
      </div>
    </div>
  );
}
