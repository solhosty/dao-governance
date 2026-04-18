"use client";

import { notFound } from "next/navigation";
import { getAddress } from "viem";
import { useReadContract } from "wagmi";

import { Breadcrumbs } from "@/components/navigation/breadcrumbs";
import { BondingCurveChart } from "@/components/market/bonding-curve-chart";
import { BuyTokenForm } from "@/components/market/buy-token-form";
import { daoFactoryAbi } from "@/lib/abi/daoFactory";
import { daoGovernanceTokenAbi } from "@/lib/abi/daoGovernanceToken";
import { daoTokenMarketAbi } from "@/lib/abi/daoTokenMarket";
import { DAO_FACTORY_ADDRESS } from "@/lib/contracts";

type TokenPageProps = {
  params: {
    token: string;
  };
};

export default function TokenMarketPage({ params }: TokenPageProps) {
  if (!DAO_FACTORY_ADDRESS) {
    notFound();
  }

  let marketAddress: `0x${string}`;
  try {
    marketAddress = getAddress(params.token);
  } catch {
    notFound();
  }

  const { data: totalDaos, isLoading: isTotalDaosLoading } = useReadContract({
    abi: daoFactoryAbi,
    address: DAO_FACTORY_ADDRESS,
    functionName: "totalDAOs",
  });

  const { data: listedDaos, isLoading: isListedDaosLoading } = useReadContract({
    abi: daoFactoryAbi,
    address: DAO_FACTORY_ADDRESS,
    functionName: "listDAOs",
    args: totalDaos !== undefined ? [0n, totalDaos] : undefined,
    query: {
      enabled: totalDaos !== undefined,
    },
  });

  const isMarketVerificationLoading =
    isTotalDaosLoading || (totalDaos !== undefined && isListedDaosLoading);

  const isKnownMarket =
    listedDaos?.some((dao) => {
      try {
        return getAddress(dao.market) === marketAddress;
      } catch {
        return false;
      }
    }) ?? false;

  const { data: basePrice } = useReadContract({
    abi: daoTokenMarketAbi,
    address: marketAddress,
    functionName: "basePriceWei",
    query: { enabled: isKnownMarket },
  });

  const { data: slope } = useReadContract({
    abi: daoTokenMarketAbi,
    address: marketAddress,
    functionName: "slopeWei",
    query: { enabled: isKnownMarket },
  });

  const { data: tokenAddress } = useReadContract({
    abi: daoTokenMarketAbi,
    address: marketAddress,
    functionName: "token",
    query: { enabled: isKnownMarket },
  });

  const tokenContractAddress = tokenAddress ?? ("0x0000000000000000000000000000000000000000" as const);

  const { data: tokenSymbol, isLoading: isTokenSymbolLoading } = useReadContract({
    abi: daoGovernanceTokenAbi,
    address: tokenContractAddress,
    functionName: "symbol",
    query: { enabled: tokenAddress !== undefined },
  });

  const resolvedSymbol =
    tokenSymbol && tokenSymbol.trim().length > 0
      ? tokenSymbol.trim().toUpperCase()
      : isTokenSymbolLoading
        ? "..."
        : "TOKEN";

  if (isMarketVerificationLoading || totalDaos === undefined || listedDaos === undefined) {
    return (
      <main className="space-y-4">
        <Breadcrumbs
          items={[
            { label: "Home", href: "/" },
            { label: "Tokens", href: "/tokens" },
            { label: "Market" },
          ]}
          backHref="/tokens"
          backLabel="Back to Tokens"
        />
        <div className="rounded-lg border border-white/40 bg-white/60 p-4 text-sm text-slate-600 shadow-glass backdrop-blur-md">
          Verifying market address...
        </div>
      </main>
    );
  }

  if (!isKnownMarket) {
    notFound();
  }

  return (
    <main className="space-y-4">
      <Breadcrumbs
        items={[
          { label: "Home", href: "/" },
          { label: "Tokens", href: "/tokens" },
          { label: `${resolvedSymbol} Market` },
        ]}
        backHref="/tokens"
        backLabel="Back to Tokens"
      />
      <div className="grid gap-4 lg:grid-cols-[1.5fr,1fr]">
        <BondingCurveChart basePriceWei={basePrice ?? 0n} slopeWei={slope ?? 0n} />
        <BuyTokenForm marketAddress={marketAddress} tokenSymbol={resolvedSymbol} />
      </div>
    </main>
  );
}
