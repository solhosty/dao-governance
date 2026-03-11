import { QueryClient } from "@tanstack/react-query";
import { createConfig, http } from "wagmi";
import { injected } from "wagmi/connectors";
import { mainnet, sepolia, localhost } from "wagmi/chains";

const localRpc = process.env["NEXT_PUBLIC_LOCAL_RPC_URL"] ?? "http://127.0.0.1:8545";
const sepoliaRpc = process.env["NEXT_PUBLIC_SEPOLIA_RPC_URL"];

export const wagmiConfig = createConfig({
  chains: [sepolia, localhost, mainnet],
  transports: {
    [sepolia.id]: http(sepoliaRpc),
    [localhost.id]: http(localRpc),
    [mainnet.id]: http(),
  },
  connectors: [injected()],
  ssr: true,
});

export const queryClient = new QueryClient();
