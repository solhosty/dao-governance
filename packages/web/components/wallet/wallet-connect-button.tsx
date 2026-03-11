"use client";

import { useAccount, useConnect, useDisconnect } from "wagmi";

function shortenAddress(address: string): string {
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

export function WalletConnectButton() {
  const { address, isConnected } = useAccount();
  const { connectors, connect, isPending } = useConnect();
  const { disconnect } = useDisconnect();

  if (isConnected && address) {
    return (
      <div className="flex items-center gap-2 text-sm">
        <span className="rounded-md border border-white/40 bg-white/60 px-2 py-1 text-xs shadow-glass">
          {shortenAddress(address)}
        </span>
        <button
          className="rounded-md border border-slate-300 bg-white px-2 py-1 text-xs hover:bg-slate-50"
          onClick={() => disconnect()}
          type="button"
        >
          Disconnect
        </button>
      </div>
    );
  }

  return (
    <div className="flex items-center gap-2">
      {connectors.map((connector) => (
        <button
          key={connector.uid}
          className="rounded-md bg-slate-900 px-3 py-1.5 text-xs text-white disabled:opacity-60"
          disabled={isPending}
          onClick={() => connect({ connector })}
          type="button"
        >
          Connect {connector.name}
        </button>
      ))}
    </div>
  );
}
