"use client";

import { useState } from "react";
import { encodeFunctionData, getAddress } from "viem";
import { useWaitForTransactionReceipt, useWriteContract } from "wagmi";

import { daoAbi } from "@/lib/abi/dao";
import { daoTokenMarketAbi } from "@/lib/abi/daoTokenMarket";

type CreateProposalModalProps = {
  daoAddress: `0x${string}`;
  marketAddress: `0x${string}`;
};

export function CreateProposalModal({ daoAddress, marketAddress }: CreateProposalModalProps) {
  const [basePrice, setBasePrice] = useState("0.0002");
  const [slope, setSlope] = useState("0.00002");
  const [description, setDescription] = useState("Adjust bonding curve parameters");
  const { data: hash, isPending, writeContract } = useWriteContract();
  const { isLoading: isConfirming } = useWaitForTransactionReceipt({ hash });

  return (
    <div className="rounded-lg border border-white/40 bg-white/60 p-4 shadow-glass backdrop-blur-md">
      <h3 className="mb-3 text-lg font-semibold">Create Proposal</h3>
      <div className="grid gap-3">
        <input
          className="rounded-md border border-slate-300 bg-white px-3 py-2 text-sm"
          value={basePrice}
          onChange={(event) => setBasePrice(event.target.value)}
          placeholder="Base price in ETH"
        />
        <input
          className="rounded-md border border-slate-300 bg-white px-3 py-2 text-sm"
          value={slope}
          onChange={(event) => setSlope(event.target.value)}
          placeholder="Slope in ETH"
        />
        <textarea
          className="rounded-md border border-slate-300 bg-white px-3 py-2 text-sm"
          value={description}
          onChange={(event) => setDescription(event.target.value)}
          placeholder="Proposal description"
        />
        <button
          className="rounded-md bg-slate-900 px-4 py-2 text-sm text-white disabled:opacity-60"
          disabled={isPending || isConfirming}
          onClick={() => {
            const baseWei = BigInt(Math.floor(Number(basePrice) * 1e18));
            const slopeWei = BigInt(Math.floor(Number(slope) * 1e18));
            const calldata = encodeFunctionData({
              abi: daoTokenMarketAbi,
              functionName: "setCurveParams",
              args: [baseWei, slopeWei],
            });

            writeContract({
              abi: daoAbi,
              address: getAddress(daoAddress),
              functionName: "propose",
              args: [[marketAddress], [0n], [calldata], description],
            });
          }}
        >
          {isPending || isConfirming ? "Submitting..." : "Submit Proposal"}
        </button>
        {hash ? <p className="text-xs text-slate-500">Tx: {hash}</p> : null}
      </div>
    </div>
  );
}
