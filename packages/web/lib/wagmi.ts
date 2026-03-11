import { getDefaultConfig } from "@rainbow-me/rainbowkit";
import { QueryClient } from "@tanstack/react-query";
import { http } from "wagmi";
import { mainnet, sepolia, localhost } from "wagmi/chains";

const localRpc = process.env["NEXT_PUBLIC_LOCAL_RPC_URL"] ?? "http://127.0.0.1:8545";
const sepoliaRpc = process.env["NEXT_PUBLIC_SEPOLIA_RPC_URL"];
const walletConnectProjectId = process.env["NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID"] ?? "demo";
const chains = [sepolia, localhost, mainnet] as const;

export const wagmiConfig = getDefaultConfig({
  appName: "DAO Governance Studio",
  projectId: walletConnectProjectId,
  chains,
  transports: {
    [sepolia.id]: http(sepoliaRpc),
    [localhost.id]: http(localRpc),
    [mainnet.id]: http(),
  },
  ssr: true,
});

export const queryClient = new QueryClient();
