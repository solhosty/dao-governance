"use client";

import { notFound } from "next/navigation";
import { getAddress } from "viem";
import { useReadContract } from "wagmi";

import { Breadcrumbs } from "@/components/navigation/breadcrumbs";
import { BondingCurveChart } from "@/components/market/bonding-curve-chart";
import { BuyTokenForm } from "@/components/market/buy-token-form";
import { daoTokenMarketAbi } from "@/lib/abi/daoTokenMarket";

type TokenPageProps = {
  params: {
    token: string;
  };
};

export default function TokenMarketPage({ params }: TokenPageProps) {
  let marketAddress: `0x${string}`;
  try {
    marketAddress = getAddress(params.token);
  } catch {
    notFound();
  }

  const { data: basePrice } = useReadContract({
    abi: daoTokenMarketAbi,
    address: marketAddress,
    functionName: "basePriceWei",
  });

  const { data: slope } = useReadContract({
    abi: daoTokenMarketAbi,
    address: marketAddress,
    functionName: "slopeWei",
  });

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
      <div className="grid gap-4 lg:grid-cols-[1.5fr,1fr]">
        <BondingCurveChart basePriceWei={basePrice ?? 0n} slopeWei={slope ?? 0n} />
        <BuyTokenForm marketAddress={marketAddress} />
      </div>
    </main>
  );
}
