"use client";

import { useMemo, useState } from "react";
import { getAddress } from "viem";
import { useReadContract, useWriteContract } from "wagmi";

import { CreateProposalModal } from "@/components/dao/create-proposal-modal";
import { Breadcrumbs } from "@/components/navigation/breadcrumbs";
import { EmptyState } from "@/components/ui/empty-state";
import { daoAbi } from "@/lib/abi/dao";
import { daoFactoryAbi } from "@/lib/abi/daoFactory";
import { DAO_FACTORY_ADDRESS } from "@/lib/contracts";

type DAOPageProps = {
  params: {
    dao: string;
  };
};

export default function DaoDetailPage({ params }: DAOPageProps) {
  const [proposalId, setProposalId] = useState("");

  const parsedDaoId = useMemo(() => {
    if (/^\d+$/.test(params.dao)) {
      return BigInt(params.dao);
    }
    return undefined;
  }, [params.dao]);

  const { data: info } = useReadContract({
    abi: daoFactoryAbi,
    address: DAO_FACTORY_ADDRESS,
    functionName: "getDAO",
    args: parsedDaoId !== undefined ? [parsedDaoId] : undefined,
    query: { enabled: Boolean(DAO_FACTORY_ADDRESS && parsedDaoId !== undefined) },
  });

  const daoAddress = useMemo(() => {
    if (info?.dao) {
      return getAddress(info.dao);
    }
    try {
      return getAddress(params.dao);
    } catch {
      return undefined;
    }
  }, [info?.dao, params.dao]);

  const parsedProposalId = useMemo(() => {
    if (/^\d+$/.test(proposalId)) {
      return BigInt(proposalId);
    }
    return undefined;
  }, [proposalId]);

  const { data: state } = useReadContract({
    abi: daoAbi,
    address: daoAddress,
    functionName: "state",
    args: parsedProposalId !== undefined ? [parsedProposalId] : undefined,
    query: { enabled: Boolean(daoAddress && parsedProposalId !== undefined) },
  });

  const { writeContract, isPending } = useWriteContract();

  if (!daoAddress) {
    return (
      <main className="space-y-4">
        <Breadcrumbs
          items={[
            { label: "Home", href: "/" },
            { label: "My DAOs", href: "/my-daos" },
            { label: "DAO detail" },
          ]}
          backHref="/my-daos"
          backLabel="Back to My DAOs"
        />
        <EmptyState
          title="DAO not found"
          description="Provide a DAO address or numeric ID to continue."
          cta={{ href: "/my-daos", label: "Open My DAOs" }}
          secondaryCta={{ href: "/tokens", label: "Browse token markets" }}
        />
      </main>
    );
  }

  const marketAddress = info ? getAddress(info.market) : undefined;

  return (
    <main className="space-y-4">
      <Breadcrumbs
        items={[
          { label: "Home", href: "/" },
          { label: "My DAOs", href: "/my-daos" },
          { label: "DAO detail" },
        ]}
        backHref="/my-daos"
        backLabel="Back to My DAOs"
      />
      <h2 className="text-2xl font-semibold">DAO Detail</h2>
      <p className="rounded-md border border-white/40 bg-white/60 px-3 py-2 text-xs shadow-glass">
        DAO address: {daoAddress}
      </p>

      {marketAddress ? (
        <CreateProposalModal daoAddress={daoAddress} marketAddress={marketAddress} />
      ) : null}

      <section className="rounded-lg border border-white/40 bg-white/60 p-4 shadow-glass backdrop-blur-md">
        <h3 className="mb-3 text-lg font-semibold">Vote on Proposal</h3>
        <div className="grid gap-3">
          <input
            className="rounded-md border border-slate-300 bg-white px-3 py-2 text-sm"
            value={proposalId}
            onChange={(event) => setProposalId(event.target.value)}
            placeholder="Proposal ID"
          />
          {parsedProposalId === undefined ? (
            <EmptyState
              title="No proposal selected"
              description="Enter a proposal ID to view status and cast a vote, or create a new proposal."
              {...(marketAddress
                ? { cta: { href: `/tokens/${marketAddress}`, label: "Open market" } }
                : {})}
            />
          ) : (
            <>
              <p className="text-xs text-slate-500">
                Current proposal state: {String(state ?? "no proposal activity yet")}
              </p>
              <button
                className="rounded-md bg-slate-900 px-4 py-2 text-sm text-white disabled:opacity-60"
                disabled={isPending}
                onClick={() => {
                  writeContract({
                    abi: daoAbi,
                    address: daoAddress,
                    functionName: "castVote",
                    args: [parsedProposalId, 1],
                  });
                }}
              >
                Cast For Vote
              </button>
            </>
          )}
        </div>
      </section>
    </main>
  );
}
