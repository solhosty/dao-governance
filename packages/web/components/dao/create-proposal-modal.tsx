"use client";

import { useMemo, useState } from "react";
import { encodeFunctionData, formatEther, getAddress, parseEther } from "viem";
import { useReadContract, useWaitForTransactionReceipt, useWriteContract } from "wagmi";

import { daoAbi } from "@/lib/abi/dao";
import { daoTokenMarketAbi } from "@/lib/abi/daoTokenMarket";

type CreateProposalModalProps = {
  daoAddress: `0x${string}`;
  marketAddress: `0x${string}`;
};

export function CreateProposalModal({ daoAddress, marketAddress }: CreateProposalModalProps) {
  const [basePrice, setBasePrice] = useState("0.00001");
  const [slope, setSlope] = useState("0.0000001");
  const [description, setDescription] = useState("Adjust bonding curve parameters");
  const [error, setError] = useState<string | null>(null);
  const { data: hash, isPending, writeContract } = useWriteContract();
  const { isLoading: isConfirming } = useWaitForTransactionReceipt({ hash });

  const { data: circulatingSupply } = useReadContract({
    abi: daoTokenMarketAbi,
    address: marketAddress,
    functionName: "circulatingSupplyTokens",
  });

  const basePriceWei = useMemo(() => {
    if (!/^\d+(\.\d{1,18})?$/.test(basePrice.trim())) {
      return null;
    }

    try {
      return parseEther(basePrice.trim());
    } catch {
      return null;
    }
  }, [basePrice]);

  const slopeWei = useMemo(() => {
    if (!/^\d+(\.\d{1,18})?$/.test(slope.trim())) {
      return null;
    }

    try {
      return parseEther(slope.trim());
    } catch {
      return null;
    }
  }, [slope]);

  const pricingPreview = useMemo(() => {
    if (basePriceWei === null || slopeWei === null || circulatingSupply === undefined) {
      return null;
    }

    const costForTokens = (tokensToBuy: bigint) => {
      const linearCost = tokensToBuy * basePriceWei;
      const supplyComponent = tokensToBuy * circulatingSupply;
      const progressiveComponent = (tokensToBuy * (tokensToBuy - 1n)) / 2n;
      return linearCost + slopeWei * (supplyComponent + progressiveComponent);
    };

    return [1n, 10n, 100n].map((tokens) => ({ tokens, costWei: costForTokens(tokens) }));
  }, [basePriceWei, circulatingSupply, slopeWei]);

  const submitProposal = () => {
    setError(null);

    if (basePriceWei === null || slopeWei === null) {
      setError("Base price and slope must be valid ETH amounts with up to 18 decimals");
      return;
    }

    if (basePriceWei <= 0n) {
      setError("Base price must be greater than zero");
      return;
    }

    if (basePriceWei > 10_000_000_000_000_000n) {
      setError("Base price must be at most 0.01 ETH");
      return;
    }

    if (slopeWei > 1_000_000_000_000_000n) {
      setError("Slope must be at most 0.001 ETH");
      return;
    }

    const calldata = encodeFunctionData({
      abi: daoTokenMarketAbi,
      functionName: "setCurveParams",
      args: [basePriceWei, slopeWei],
    });

    writeContract({
      abi: daoAbi,
      address: getAddress(daoAddress),
      functionName: "propose",
      args: [[marketAddress], [0n], [calldata], description],
    });
  };

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
          onClick={submitProposal}
        >
          {isPending || isConfirming ? "Submitting..." : "Submit Proposal"}
        </button>
        {pricingPreview ? (
          <p className="rounded-md border border-slate-200 bg-slate-50 px-3 py-2 text-xs text-slate-600">
            Repricing preview: {pricingPreview.map(({ tokens, costWei }) => `${tokens.toString()} token${tokens === 1n ? "" : "s"} ≈ ${formatEther(costWei)} ETH`).join(" | ")}
          </p>
        ) : (
          <p className="rounded-md border border-slate-200 bg-slate-50 px-3 py-2 text-xs text-slate-600">
            Enter valid curve values to preview expected buy costs
          </p>
        )}
        {error ? <p className="text-xs text-red-600">{error}</p> : null}
        {hash ? <p className="text-xs text-slate-500">Tx: {hash}</p> : null}
      </div>
    </div>
  );
}
