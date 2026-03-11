import { describe, expect, test } from "bun:test";
import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import * as sdk from "../src/index";

const ABI_NAMES = [
  "YellowToken",
  "NodeRegistry",
  "AppRegistry",
  "YellowGovernor",
  "TimelockController",
  "Treasury",
  "Faucet",
  "ILock",
  "ISlash",
];

const JSON_DIR = join(import.meta.dirname, "..", "abi");

describe("JSON ABI files", () => {
  test("every exported ABI has a corresponding JSON file", async () => {
    const files = (await readdir(JSON_DIR)).filter((f) => f.endsWith(".json"));
    const expected = ABI_NAMES.map((n) => `${n}.json`);
    expect(files.sort()).toEqual(expected.sort());
  });

  test("JSON files are valid JSON arrays", async () => {
    for (const name of ABI_NAMES) {
      const raw = await readFile(join(JSON_DIR, `${name}.json`), "utf-8");
      const parsed = JSON.parse(raw);
      expect(Array.isArray(parsed)).toBe(true);
      expect(parsed.length).toBeGreaterThan(0);
    }
  });

  test("JSON and TS exports are identical", async () => {
    for (const name of ABI_NAMES) {
      const raw = await readFile(join(JSON_DIR, `${name}.json`), "utf-8");
      const jsonAbi = JSON.parse(raw);
      const tsAbi = (sdk as Record<string, unknown>)[`${name}Abi`];
      expect(jsonAbi).toEqual(tsAbi);
    }
  });
});
