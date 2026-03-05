export type ContractAddresses = {
  yellowToken: `0x${string}`;
  nodeRegistry: `0x${string}`;
  appRegistry: `0x${string}`;
  governor: `0x${string}`;
  timelock: `0x${string}`;
  treasury: `0x${string}`;
  faucet?: `0x${string}`;
};

/**
 * Deployed contract addresses keyed by chain ID.
 *
 * Update these after each deployment.
 */
export const addresses: Record<number, Partial<ContractAddresses>> = {
  // Ethereum Mainnet
  1: {
    yellowToken: "0x236eB848C95b231299B4AA9f56c73D6893462720",
  },
  // Sepolia
  11155111: {
    yellowToken: "0x236eB848C95b231299B4AA9f56c73D6893462720",
    faucet: "0x914abaDC0e36e03f29e4F1516951125c774dBAc8",
  },
};
