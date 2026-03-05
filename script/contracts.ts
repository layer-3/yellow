/**
 * Shared contract registry used by extract-abis.ts and build-docs.ts.
 *
 * Maps SDK export name → Foundry artifact path (relative to out/).
 */
export const CONTRACTS: Record<string, string> = {
  YellowToken: "Token.sol/YellowToken.json",
  NodeRegistry: "NodeRegistry.sol/NodeRegistry.json",
  AppRegistry: "AppRegistry.sol/AppRegistry.json",
  YellowGovernor: "Governor.sol/YellowGovernor.json",
  TimelockController: "TimelockController.sol/TimelockController.json",
  Treasury: "Treasury.sol/Treasury.json",
  Faucet: "Faucet.sol/Faucet.json",
  ILock: "ILock.sol/ILock.json",
  ISlash: "ISlash.sol/ISlash.json",
};

/** Human-readable label for each contract. */
export const LABELS: Record<string, string> = {
  YellowToken: "ERC-20 + EIP-2612 permit",
  NodeRegistry: "Staking + voting (ILock + IVotes)",
  AppRegistry: "Collateral + slashing (ILock + ISlash + AccessControl)",
  YellowGovernor: "Governance (Governor + extensions)",
  TimelockController: "Delayed execution",
  Treasury: "Foundation vault",
  Faucet: "Testnet faucet",
  ILock: "Lock/unlock interface (shared by both registries)",
  ISlash: "Slash interface",
};

/** Chain names for addresses page. */
export const CHAINS: Record<number, { name: string; explorer: string }> = {
  1: { name: "Ethereum Mainnet", explorer: "https://etherscan.io/address" },
  11155111: { name: "Sepolia Testnet", explorer: "https://sepolia.etherscan.io/address" },
};

/** Display name for address keys. */
export const ADDRESS_LABELS: Record<string, string> = {
  yellowToken: "YellowToken",
  nodeRegistry: "NodeRegistry",
  appRegistry: "AppRegistry",
  governor: "YellowGovernor",
  timelock: "TimelockController",
  treasury: "Treasury",
  faucet: "Faucet",
};
