"use client";

import Link from "next/link";
import { useMemo } from "react";
import { useAccount, useReadContract } from "wagmi";

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
    return <p>Set NEXT_PUBLIC_DAO_FACTORY_ADDRESS to load your DAO dashboard.</p>;
  }

  return (
    <main className="space-y-4">
      <h2 className="text-2xl font-semibold">My DAOs</h2>
      <p className="text-sm text-slate-600">
        Connected wallet: {address ?? "Connect wallet in your preferred connector"}
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
