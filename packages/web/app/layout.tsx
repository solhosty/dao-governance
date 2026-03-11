import type { Metadata } from "next";
import Link from "next/link";
import type { ReactNode } from "react";

import { Web3Provider } from "@/components/providers/web3-provider";
import { WalletConnectButton } from "@/components/wallet/wallet-connect-button";

import "@rainbow-me/rainbowkit/styles.css";
import "../styles/globals.css";

export const metadata: Metadata = {
  title: "DAO Governance Studio",
  description: "Factory-driven DAO governance with bonding curve token markets",
};

type RootLayoutProps = {
  children: ReactNode;
};

export default function RootLayout({ children }: RootLayoutProps) {
  return (
    <html lang="en">
      <body className="min-h-screen bg-background text-foreground antialiased">
        <Web3Provider>
          <div className="mx-auto max-w-6xl px-6 py-6">
            <header className="mb-8 flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-white/30 bg-white/50 px-4 py-3 shadow-glass backdrop-blur-md">
              <h1 className="text-lg font-semibold tracking-tight">DAO Governance Studio</h1>
              <div className="flex flex-wrap items-center gap-3">
                <nav className="flex gap-3 text-sm">
                  <Link href="/">Home</Link>
                  <Link href="/tokens">Tokens</Link>
                  <Link href="/my-daos">My DAOs</Link>
                </nav>
                <WalletConnectButton />
              </div>
            </header>
            {children}
          </div>
        </Web3Provider>
      </body>
    </html>
  );
}
