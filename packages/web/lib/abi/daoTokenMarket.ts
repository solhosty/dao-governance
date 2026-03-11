export const daoTokenMarketAbi = [
  {
    type: "function",
    name: "basePriceWei",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "slopeWei",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "quoteBuy",
    stateMutability: "view",
    inputs: [{ name: "ethAmount", type: "uint256" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "buy",
    stateMutability: "payable",
    inputs: [{ name: "minTokensOut", type: "uint256" }],
    outputs: [{ name: "tokensOut", type: "uint256" }],
  },
  {
    type: "function",
    name: "setCurveParams",
    stateMutability: "nonpayable",
    inputs: [
      { name: "basePriceWei", type: "uint256" },
      { name: "slopeWei", type: "uint256" },
    ],
    outputs: [],
  },
] as const;
