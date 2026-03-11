"use client";

import { useRouter } from "next/navigation";
import { type FormEvent, useMemo, useState } from "react";
import { parseEventLogs } from "viem";
import { usePublicClient, useWriteContract } from "wagmi";

import { daoFactoryAbi } from "@/lib/abi/daoFactory";
import { DAO_FACTORY_ADDRESS, DEFAULT_CHAIN_ID } from "@/lib/contracts";

const DEFAULT_BASE_PRICE_WEI = 100_000_000_000_000n;
const DEFAULT_SLOPE_WEI = 10_000_000_000_000n;
const DEFAULT_QUORUM_NUMERATOR = 4n;

export function CreateDaoForm() {
  const router = useRouter();
  const publicClient = usePublicClient({ chainId: DEFAULT_CHAIN_ID });
  const { writeContractAsync, isPending } = useWriteContract();

  const [daoName, setDaoName] = useState("");
  const [tokenName, setTokenName] = useState("");
  const [tokenSymbol, setTokenSymbol] = useState("");
  const [initialSupply, setInitialSupply] = useState("1000000");
  const [error, setError] = useState<string | null>(null);
  const [txHash, setTxHash] = useState<`0x${string}` | null>(null);

  const parsedSupply = useMemo(() => {
    if (!/^\d+$/.test(initialSupply)) {
      return null;
    }

    const parsed = BigInt(initialSupply);
    if (parsed <= 0n) {
      return null;
    }

    return parsed;
  }, [initialSupply]);

  async function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);

    if (!DAO_FACTORY_ADDRESS) {
      setError("Factory address is not configured");
      return;
    }

    if (daoName.trim().length === 0) {
      setError("DAO name is required");
      return;
    }

    if (tokenName.trim().length === 0) {
      setError("Token name is required");
      return;
    }

    if (tokenSymbol.trim().length < 2 || tokenSymbol.trim().length > 12) {
      setError("Token symbol must be between 2 and 12 characters");
      return;
    }

    if (parsedSupply === null) {
      setError("Initial supply must be a positive whole number");
      return;
    }

    if (!publicClient) {
      setError("Wallet client is unavailable on the selected chain");
      return;
    }

    try {
      const hash = await writeContractAsync({
        abi: daoFactoryAbi,
        address: DAO_FACTORY_ADDRESS,
        functionName: "createDAO",
        chainId: DEFAULT_CHAIN_ID,
        args: [
          daoName.trim(),
          tokenName.trim(),
          tokenSymbol.trim().toUpperCase(),
          parsedSupply,
          DEFAULT_BASE_PRICE_WEI,
          DEFAULT_SLOPE_WEI,
          DEFAULT_QUORUM_NUMERATOR,
        ],
      });

      setTxHash(hash);
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      const events = parseEventLogs({
        abi: daoFactoryAbi,
        logs: receipt.logs,
        eventName: "DAOCreated",
      });
      const daoId = events[0]?.args.daoId ?? null;

      if (daoId === null) {
        setError("Transaction confirmed but DAO id could not be resolved");
        return;
      }

      router.push(`/dao/${daoId.toString()}`);
    } catch (submitError) {
      const message = submitError instanceof Error ? submitError.message : "Transaction failed";
      setError(message);
    }
  }

  return (
    <section className="rounded-2xl border border-white/40 bg-white/60 p-6 shadow-glass backdrop-blur-md">
      <h3 className="text-xl font-semibold">Create DAO</h3>
      <p className="mt-1 text-sm text-slate-600">
        Deploy governance, token, and market contracts through the factory
      </p>
      <form className="mt-5 grid gap-3" onSubmit={onSubmit}>
        <label className="grid gap-1 text-sm">
          <span>DAO name</span>
          <input
            className="rounded-md border border-slate-300 bg-white px-3 py-2"
            value={daoName}
            onChange={(event) => setDaoName(event.target.value)}
            placeholder="Atlas Research Collective"
          />
        </label>
        <label className="grid gap-1 text-sm">
          <span>Token name</span>
          <input
            className="rounded-md border border-slate-300 bg-white px-3 py-2"
            value={tokenName}
            onChange={(event) => setTokenName(event.target.value)}
            placeholder="Atlas Governance Token"
          />
        </label>
        <div className="grid gap-3 md:grid-cols-2">
          <label className="grid gap-1 text-sm">
            <span>Token symbol</span>
            <input
              className="rounded-md border border-slate-300 bg-white px-3 py-2 uppercase"
              value={tokenSymbol}
              onChange={(event) => setTokenSymbol(event.target.value)}
              placeholder="ATLAS"
            />
          </label>
          <label className="grid gap-1 text-sm">
            <span>Initial supply</span>
            <input
              className="rounded-md border border-slate-300 bg-white px-3 py-2"
              inputMode="numeric"
              value={initialSupply}
              onChange={(event) => setInitialSupply(event.target.value)}
              placeholder="1000000"
            />
          </label>
        </div>
        <button
          className="mt-2 w-fit rounded-md bg-slate-900 px-4 py-2 text-sm font-medium text-white disabled:opacity-60"
          disabled={isPending}
          type="submit"
        >
          {isPending ? "Submitting..." : "Create DAO"}
        </button>
        {txHash ? (
          <p className="text-xs text-slate-500">Pending transaction: {txHash}</p>
        ) : null}
        {error ? (
          <p className="rounded-md border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700">{error}</p>
        ) : null}
      </form>
    </section>
  );
}
