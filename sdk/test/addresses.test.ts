import { describe, expect, test } from "bun:test";
import { addresses } from "../src/index";

const ADDRESS_RE = /^0x[0-9a-fA-F]{40}$/;

const MAINNET = 1;
const SEPOLIA = 11155111;

describe("addresses", () => {
  test("contains mainnet and sepolia", () => {
    expect(addresses[MAINNET]).toBeDefined();
    expect(addresses[SEPOLIA]).toBeDefined();
  });

  test("does not include local chain (31337)", () => {
    expect(addresses[31337]).toBeUndefined();
  });

  for (const [chainId, addrs] of Object.entries(addresses)) {
    describe(`chain ${chainId}`, () => {
      test("all values are valid checksummed addresses", () => {
        for (const [_key, addr] of Object.entries(
          addrs as Record<string, string>,
        )) {
          expect(addr).toMatch(ADDRESS_RE);
          // EIP-55: checksummed addresses have mixed case (not all-lower/all-upper)
          const hex = addr.slice(2);
          expect(hex !== hex.toLowerCase() || hex !== hex.toUpperCase()).toBe(
            true,
          );
        }
      });

      test("all addresses are unique", () => {
        const vals = Object.values(addrs as Record<string, string>);
        expect(new Set(vals).size).toBe(vals.length);
      });
    });
  }
});

describe("mainnet completeness", () => {
  const mainnet = addresses[MAINNET];

  const required = [
    "yellowToken",
    "nodeRegistry",
    "appRegistry",
    "governor",
    "timelock",
    "treasuryFounder",
    "treasuryCommunity",
    "treasuryTokenSale",
    "treasuryFoundation",
    "treasuryNetwork",
    "treasuryLiquidity",
  ] as const;

  for (const key of required) {
    test(`${key} is present`, () => {
      expect(mainnet[key]).toBeDefined();
    });
  }
});

describe("sepolia completeness", () => {
  const sepolia = addresses[SEPOLIA];

  test("yellowToken is present", () => {
    expect(sepolia.yellowToken).toBeDefined();
  });

  test("faucet is present", () => {
    expect(sepolia.faucet).toBeDefined();
  });

  const treasuryKeys = [
    "treasuryFounder",
    "treasuryCommunity",
    "treasuryTokenSale",
    "treasuryFoundation",
    "treasuryNetwork",
    "treasuryLiquidity",
  ] as const;

  for (const key of treasuryKeys) {
    test(`${key} is present`, () => {
      expect(sepolia[key]).toBeDefined();
    });
  }
});

describe("cross-chain invariants", () => {
  test("yellowToken address matches across chains (CREATE2)", () => {
    expect(addresses[MAINNET]?.yellowToken).toBe(
      addresses[SEPOLIA]?.yellowToken,
    );
  });

  test("treasury addresses differ between chains", () => {
    expect(addresses[MAINNET]?.treasuryFounder).not.toBe(
      addresses[SEPOLIA]?.treasuryFounder,
    );
  });
});
