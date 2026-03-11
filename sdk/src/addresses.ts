export type ContractAddresses = {
  yellowToken: `0x${string}`;
  nodeRegistry: `0x${string}`;
  appRegistry: `0x${string}`;
  governor: `0x${string}`;
  timelock: `0x${string}`;
  treasuryFounder: `0x${string}`;
  treasuryCommunity: `0x${string}`;
  treasuryTokenSale: `0x${string}`;
  treasuryFoundation: `0x${string}`;
  treasuryNetwork: `0x${string}`;
  treasuryLiquidity: `0x${string}`;
  faucet?: `0x${string}`;
};

/**
 * Deployed contract addresses keyed by chain ID.
 *
 * Auto-generated from Forge broadcast artifacts — do not edit manually.
 */
export const addresses: Record<number, Partial<ContractAddresses>> = {
  // Ethereum Mainnet
  1: {
    yellowToken: "0x236eB848C95b231299B4AA9f56c73D6893462720",
    nodeRegistry: "0xB0C7aA4ca9ffF4A48B184d8425eb5B6Fa772d820",
    appRegistry: "0x5A70029B843eE272A2392acE21DA392693eef1c6",
    governor: "0x7Ce0AE21E11dFEDA2F6e4D8bF2749E4061119512",
    timelock: "0x9530896F9622b925c37dF5Cfa271cc9deBB226b7",
    treasuryFounder: "0x914abaDC0e36e03f29e4F1516951125c774dBAc8",
    treasuryCommunity: "0xAec5157545635A7523EFB5ABe3a37F52dB7DE72e",
    treasuryTokenSale: "0xd572f3a0967856a09054578439aCe81B2f2ff88B",
    treasuryFoundation: "0xfD8E336757aE9cDc0766264064B51492814fCd47",
    treasuryNetwork: "0xE277830b3444EA2cfee2B95F780c971222DEcfA9",
    treasuryLiquidity: "0xA8f52FFe4DeE9565505f8E390163A335D6A2F708",
  },
  // Sepolia Testnet
  11155111: {
    yellowToken: "0x236eB848C95b231299B4AA9f56c73D6893462720",
    treasuryFounder: "0x6f4eeD96cA1388803A9923476a0F5e19703d1e7C",
    treasuryCommunity: "0x3939a80FE4cc2F16F1294a995A4255B68d8c1F27",
    treasuryTokenSale: "0x9b4742c0aEFfE3DD16c924f4630F6964fe1ad420",
    treasuryFoundation: "0xbb5006195974B1d3c36e46EA2D7665FE1E65ADf2",
    treasuryNetwork: "0x72F4461A79AB44BbCf1E70c1e3CE9a5a2C2e1920",
    treasuryLiquidity: "0x5825BD45C3f495391f4a7690be581b1c91Ac6959",
    faucet: "0x914abaDC0e36e03f29e4F1516951125c774dBAc8",
  },
};
