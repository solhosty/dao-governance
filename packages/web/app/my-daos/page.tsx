"use client";

import Link from "next/link";
import { useMemo } from "react";
import { useAccount, useReadContract } from "wagmi";

import { Breadcrumbs } from "@/components/navigation/breadcrumbs";
import { EmptyState } from "@/components/ui/empty-state";
import { daoFactoryAbi } from "@/lib/abi/daoFactory";
import { DAO_FACTORY_ADDRESS } from "@/lib/contracts";

export default function MyDaosPage() {
  const { address } = useAccount();

  const { data: total } = useReadContract({
    abi: daoFactoryAbi,
    address: DAO_FACTORY_ADDRESS,
    functionName: "totalDAOs",
    query: { enabled: Boolean(DAO_FACTORY_ADDRESS) },
  });

  const ids = useMemo(() => {
    const totalDaos = Number(total ?? 0n);
    return Array.from({ length: totalDaos }, (_, index) => BigInt(index));
  }, [total]);

  if (!DAO_FACTORY_ADDRESS) {
    return (
      <main className="space-y-4">
        <Breadcrumbs items={[{ label: "Home", href: "/" }, { label: "My DAOs" }]} backHref="/" />
        <EmptyState
          title="Factory address not configured"
          description="Set NEXT_PUBLIC_DAO_FACTORY_ADDRESS to load your DAO dashboard."
          cta={{ href: "/", label: "Go to Home" }}
        />
      </main>
    );
  }

  if (!address) {
    return (
      <main className="space-y-4">
        <Breadcrumbs items={[{ label: "Home", href: "/" }, { label: "My DAOs" }]} backHref="/" />
        <h2 className="text-2xl font-semibold">My DAOs</h2>
        <EmptyState
          title="Connect your wallet"
          description="Use the wallet button in the header to discover DAOs connected to your account."
          cta={{ href: "/tokens", label: "Browse token markets" }}
          secondaryCta={{ href: "/", label: "Go to Home" }}
        />
      </main>
    );
  }

  if (ids.length === 0) {
    return (
      <main className="space-y-4">
        <Breadcrumbs items={[{ label: "Home", href: "/" }, { label: "My DAOs" }]} backHref="/" />
        <h2 className="text-2xl font-semibold">My DAOs</h2>
        <EmptyState
          title="No DAOs found yet"
          description="No DAOs are discoverable right now. Explore token markets or create a DAO from the home page."
          cta={{ href: "/tokens", label: "Open token markets" }}
          secondaryCta={{ href: "/", label: "Go to Home" }}
        />
      </main>
    );
  }

  return (
    <main className="space-y-4">
      <Breadcrumbs items={[{ label: "Home", href: "/" }, { label: "My DAOs" }]} backHref="/" />
      <h2 className="text-2xl font-semibold">My DAOs</h2>
      <p className="text-sm text-slate-600">
        Connected wallet: {address}
      </p>
      <div className="grid gap-2">
        {ids.map((id) => (
          <Link
            key={id.toString()}
            href={`/dao/${id.toString()}`}
            className="rounded-md border border-white/40 bg-white/60 px-3 py-2 text-sm shadow-glass backdrop-blur-md"
          >
            DAO #{id.toString()}
          </Link>
        ))}
      </div>
    </main>
  );
}
