"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { getAddress } from "viem";
import { useAccount, usePublicClient, useReadContract } from "wagmi";

import { Breadcrumbs } from "@/components/navigation/breadcrumbs";
import { EmptyState } from "@/components/ui/empty-state";
import { daoFactoryAbi } from "@/lib/abi/daoFactory";
import { daoGovernanceTokenAbi } from "@/lib/abi/daoGovernanceToken";
import { DAO_FACTORY_ADDRESS } from "@/lib/contracts";

export default function MyDaosPage() {
  const { address } = useAccount();
  const publicClient = usePublicClient();
  const [holderBalances, setHolderBalances] = useState<Record<string, bigint>>({});

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

  useEffect(() => {
    let cancelled = false;

    async function loadHolderBalances() {
      if (!publicClient || !address || !listedDaos || listedDaos.length === 0) {
        if (!cancelled) {
          setHolderBalances({});
        }
        return;
      }

      const pairs = await Promise.all(
        listedDaos.map(async (item) => {
          try {
            const balance = await publicClient.readContract({
              abi: daoGovernanceTokenAbi,
              address: getAddress(item.token),
              functionName: "balanceOf",
              args: [address],
            });
            return [item.id.toString(), balance] as const;
          } catch {
            return [item.id.toString(), 0n] as const;
          }
        }),
      );

      if (!cancelled) {
        setHolderBalances(Object.fromEntries(pairs));
      }
    }

    void loadHolderBalances();

    return () => {
      cancelled = true;
    };
  }, [address, listedDaos, publicClient]);

  const matchingDaos = useMemo(() => {
    if (!address || !listedDaos) {
      return [];
    }

    const normalizedAddress = getAddress(address);

    return listedDaos
      .filter((item) => {
        const isCreator = getAddress(item.creator) === normalizedAddress;
        const holderBalance = holderBalances[item.id.toString()] ?? 0n;
        const isHolder = holderBalance > 0n;
        return isCreator || isHolder;
      })
      .sort((a, b) => Number(b.createdAt - a.createdAt));
  }, [address, holderBalances, listedDaos]);

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

  if ((listedDaos?.length ?? 0) === 0) {
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

  if (matchingDaos.length === 0) {
    return (
      <main className="space-y-4">
        <Breadcrumbs items={[{ label: "Home", href: "/" }, { label: "My DAOs" }]} backHref="/" />
        <h2 className="text-2xl font-semibold">My DAOs</h2>
        <EmptyState
          title="No personal DAOs found"
          description="You are not currently a creator or token holder in discoverable DAOs for this wallet."
          cta={{ href: "/tokens", label: "Browse token markets" }}
          secondaryCta={{ href: "/", label: "Go to Home" }}
        />
      </main>
    );
  }

  return (
    <main className="space-y-4">
      <Breadcrumbs items={[{ label: "Home", href: "/" }, { label: "My DAOs" }]} backHref="/" />
      <h2 className="text-2xl font-semibold">My DAOs</h2>
      <p className="text-sm text-slate-600">Connected wallet: {address}</p>
      <div className="grid gap-3 md:grid-cols-2">
        {matchingDaos.map((dao) => (
          <Link
            key={dao.id.toString()}
            href={`/dao/${dao.id.toString()}`}
            className="rounded-lg border border-white/40 bg-white/60 p-4 shadow-glass backdrop-blur-md"
          >
            <p className="text-xs text-slate-500">DAO #{dao.id.toString()}</p>
            <p className="text-sm font-semibold">{dao.name}</p>
            <p className="text-xs text-slate-600">
              {dao.tokenName} ({dao.symbol})
            </p>
            <p className="mt-2 text-xs text-slate-500">Creator: {dao.creator}</p>
          </Link>
        ))}
      </div>
    </main>
  );
}
