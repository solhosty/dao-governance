import { getAddress } from "viem";

const daoFactoryRaw = process.env["NEXT_PUBLIC_DAO_FACTORY_ADDRESS"];

export const DAO_FACTORY_ADDRESS = daoFactoryRaw
  ? getAddress(daoFactoryRaw)
  : undefined;

export const DEFAULT_CHAIN_ID = Number(process.env["NEXT_PUBLIC_CHAIN_ID"] ?? 31337);
