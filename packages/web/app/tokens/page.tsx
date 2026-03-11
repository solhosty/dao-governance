"use client";

import Link from "next/link";
import { useMemo } from "react";
import { useReadContract } from "wagmi";

import { Breadcrumbs } from "@/components/navigation/breadcrumbs";
import { EmptyState } from "@/components/ui/empty-state";
import { daoFactoryAbi } from "@/lib/abi/daoFactory";
import { DAO_FACTORY_ADDRESS } from "@/lib/contracts";

export default function TokensPage() {
  const { data: total } = useReadContract({
    abi: daoFactoryAbi,
    address: DAO_FACTORY_ADDRESS,
    functionName: "totalDAOs",
    query: { enabled: Boolean(DAO_FACTORY_ADDRESS) },
  });

  const { data: listedDaos } = useReadContract({
    abi: daoFactoryAbi,
    address: DAO_FACTORY_ADDRESS,
    functionName: "listDAOs",
    args: total !== undefined ? [0n, total] : undefined,
    query: { enabled: Boolean(DAO_FACTORY_ADDRESS && total !== undefined && total > 0n) },
  });

  const sortedDaos = useMemo(() => {
    return [...(listedDaos ?? [])].sort((a, b) => Number(b.createdAt - a.createdAt));
  }, [listedDaos]);

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

  if (sortedDaos.length === 0) {
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
        {sortedDaos.map((dao) => (
          <article
            key={dao.id.toString()}
            className="rounded-lg border border-white/40 bg-white/60 p-4 shadow-glass backdrop-blur-md"
          >
            <p className="text-xs text-slate-500">DAO #{dao.id.toString()}</p>
            <h3 className="text-lg font-semibold">{dao.name}</h3>
            <p className="text-sm text-slate-600">
              {dao.tokenName} ({dao.symbol})
            </p>
            <div className="mt-3 flex gap-2">
              <Link className="text-sm underline" href={`/tokens/${dao.market}`}>
                Open market
              </Link>
              <Link className="text-sm underline" href={`/dao/${dao.id.toString()}`}>
                Open DAO
              </Link>
            </div>
          </article>
        ))}
      </div>
    </main>
  );
}
