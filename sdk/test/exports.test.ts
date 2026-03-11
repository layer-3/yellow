import { describe, expect, test } from "bun:test";
import * as sdk from "../src/index";

const EXPECTED_ABI_EXPORTS = [
  "YellowTokenAbi",
  "NodeRegistryAbi",
  "AppRegistryAbi",
  "YellowGovernorAbi",
  "TimelockControllerAbi",
  "TreasuryAbi",
  "FaucetAbi",
  "ILockAbi",
  "ISlashAbi",
];

describe("public API surface", () => {
  test("exports exactly the expected names", () => {
    const exported = Object.keys(sdk).sort();
    const expected = [...EXPECTED_ABI_EXPORTS, "addresses"].sort();
    expect(exported).toEqual(expected);
  });

  test("no default export", () => {
    expect((sdk as Record<string, unknown>).default).toBeUndefined();
  });

  for (const name of EXPECTED_ABI_EXPORTS) {
    test(`${name} is an array`, () => {
      const abi = (sdk as Record<string, unknown>)[name];
      expect(Array.isArray(abi)).toBe(true);
    });
  }

  test("addresses is a plain object", () => {
    expect(typeof sdk.addresses).toBe("object");
    expect(Array.isArray(sdk.addresses)).toBe(false);
  });
});
