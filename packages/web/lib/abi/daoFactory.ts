export const daoFactoryAbi = [
  {
    type: "function",
    name: "createDAO",
    stateMutability: "nonpayable",
    inputs: [
      { name: "name", type: "string" },
      { name: "symbol", type: "string" },
      { name: "initialSupply", type: "uint256" },
      { name: "basePriceWei", type: "uint256" },
      { name: "slopeWei", type: "uint256" },
      { name: "quorumNumerator", type: "uint256" },
    ],
    outputs: [{ name: "daoId", type: "uint256" }],
  },
  {
    type: "function",
    name: "totalDAOs",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "getDAO",
    stateMutability: "view",
    inputs: [{ name: "daoId", type: "uint256" }],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          { name: "id", type: "uint256" },
          { name: "name", type: "string" },
          { name: "symbol", type: "string" },
          { name: "creator", type: "address" },
          { name: "token", type: "address" },
          { name: "dao", type: "address" },
          { name: "market", type: "address" },
          { name: "timelock", type: "address" },
          { name: "createdAt", type: "uint256" },
        ],
      },
    ],
  },
] as const;
