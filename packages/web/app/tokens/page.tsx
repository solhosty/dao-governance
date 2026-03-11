"use client";

import Link from "next/link";

import { useReadContract } from "wagmi";

import { Breadcrumbs } from "@/components/navigation/breadcrumbs";
import { EmptyState } from "@/components/ui/empty-state";
import { daoFactoryAbi } from "@/lib/abi/daoFactory";
import { DAO_FACTORY_ADDRESS } from "@/lib/contracts";

function DaoCard({ daoId }: { daoId: bigint }) {
  const { data } = useReadContract({
    abi: daoFactoryAbi,
    address: DAO_FACTORY_ADDRESS,
    functionName: "getDAO",
    args: [daoId],
    query: { enabled: Boolean(DAO_FACTORY_ADDRESS) },
  });

  if (!data) {
    return (
      <article className="rounded-lg border border-white/40 bg-white/50 p-4 shadow-glass backdrop-blur-md">
        Loading DAO #{String(daoId)}...
      </article>
    );
  }

  return (
    <article className="rounded-lg border border-white/40 bg-white/60 p-4 shadow-glass backdrop-blur-md">
      <p className="text-xs text-slate-500">DAO #{String(data.id)}</p>
      <h3 className="text-lg font-semibold">{data.name}</h3>
      <p className="text-sm text-slate-600">
        {data.tokenName} ({data.symbol})
      </p>
      <div className="mt-3 flex gap-2">
        <Link className="text-sm underline" href={`/tokens/${data.market}`}>
          Open market
        </Link>
        <Link className="text-sm underline" href={`/dao/${data.dao}`}>
          Open DAO
        </Link>
      </div>
    </article>
  );
}

export default function TokensPage() {
  const { data: total } = useReadContract({
    abi: daoFactoryAbi,
    address: DAO_FACTORY_ADDRESS,
    functionName: "totalDAOs",
    query: { enabled: Boolean(DAO_FACTORY_ADDRESS) },
  });

  if (!DAO_FACTORY_ADDRESS) {
    return (
      <main className="space-y-4">
        <Breadcrumbs items={[{ label: "Home", href: "/" }, { label: "Tokens" }]} backHref="/" />
        <EmptyState
          title="Factory address not configured"
          description="Set NEXT_PUBLIC_DAO_FACTORY_ADDRESS to view token markets."
          cta={{ href: "/", label: "Go to Home" }}
        />
      </main>
    );
  }

  const totalDaos = Number(total ?? 0n);

  if (totalDaos === 0) {
    return (
      <main className="space-y-4">
        <Breadcrumbs items={[{ label: "Home", href: "/" }, { label: "Tokens" }]} backHref="/" />
        <h2 className="text-2xl font-semibold">Token Markets</h2>
        <EmptyState
          title="No token markets yet"
          description="Create your first DAO to launch a market."
          cta={{ href: "/", label: "Go to Home" }}
        />
      </main>
    );
  }

  return (
    <main className="space-y-4">
      <Breadcrumbs items={[{ label: "Home", href: "/" }, { label: "Tokens" }]} backHref="/" />
      <h2 className="text-2xl font-semibold">Token Markets</h2>
      <div className="grid gap-3 md:grid-cols-2">
        {Array.from({ length: totalDaos }).map((_, index) => (
          <DaoCard key={index} daoId={BigInt(index)} />
        ))}
      </div>
    </main>
  );
}
