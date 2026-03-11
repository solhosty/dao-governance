import { QueryClient } from "@tanstack/react-query";
import { createConfig, http } from "wagmi";
import { mainnet, sepolia, localhost } from "wagmi/chains";

const localRpc = process.env["NEXT_PUBLIC_LOCAL_RPC_URL"] ?? "http://127.0.0.1:8545";

export const wagmiConfig = createConfig({
  chains: [localhost, sepolia, mainnet],
  transports: {
    [localhost.id]: http(localRpc),
    [sepolia.id]: http(),
    [mainnet.id]: http(),
  },
  ssr: true,
});

export const queryClient = new QueryClient();
