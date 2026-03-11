/**
 * Extracts deployed contract addresses from Forge broadcast artifacts
 * and writes sdk/src/addresses.ts.
 *
 * Only includes chains listed in CHAINS (script/contracts.ts) and skips
 * local (31337) deployments.
 *
 * Usage: bun run script/extract-addresses.ts
 */
import { readFile, readdir, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { CHAINS, TREASURY_KEYS } from "./contracts";

const ROOT = join(import.meta.dirname, "..");
const BROADCAST_DIR = join(ROOT, "broadcast");
const OUT_FILE = join(ROOT, "sdk", "src", "addresses.ts");

/** Maps Forge contractName → SDK address key (for non-Treasury contracts). */
const CONTRACT_MAP: Record<string, string> = {
  YellowToken: "yellowToken",
  NodeRegistry: "nodeRegistry",
  AppRegistry: "appRegistry",
  YellowGovernor: "governor",
  TimelockController: "timelock",
  Faucet: "faucet",
};

/** Canonical key order for output. */
const KEY_ORDER = [
  "yellowToken",
  "nodeRegistry",
  "appRegistry",
  "governor",
  "timelock",
  ...Object.values(TREASURY_KEYS),
  "faucet",
];

/** EIP-55 mixed-case checksum via Foundry's `cast`. */
async function toChecksumAddress(addr: string): Promise<string> {
  const proc = Bun.spawn(["cast", "to-check-sum-address", addr]);
  const text = await new Response(proc.stdout).text();
  return text.trim();
}

type Tx = {
  transactionType: string;
  contractName: string;
  contractAddress: string;
  arguments?: string[];
};

type BroadcastFile = {
  transactions: Tx[];
  chain: number;
};

async function main() {
  const addresses: Record<number, Record<string, string>> = {};

  // Scan broadcast/{Script}/{chainId}/run-latest.json
  const scripts = await readdir(BROADCAST_DIR).catch(() => [] as string[]);

  for (const script of scripts) {
    const scriptDir = join(BROADCAST_DIR, script);
    const chainDirs = await readdir(scriptDir).catch(() => [] as string[]);

    for (const chainDir of chainDirs) {
      const chainId = Number(chainDir);
      if (isNaN(chainId) || !(chainId in CHAINS)) continue;

      const filePath = join(scriptDir, chainDir, "run-latest.json");
      const raw = await readFile(filePath, "utf-8").catch(() => null);
      if (!raw) continue;

      const broadcast: BroadcastFile = JSON.parse(raw);

      for (const tx of broadcast.transactions) {
        if (tx.transactionType !== "CREATE") continue;

        let key: string | undefined;

        if (tx.contractName === "Treasury") {
          // Multiple Treasury instances — use constructor name arg to distinguish
          const name = tx.arguments?.[1];
          if (name) key = TREASURY_KEYS[name];
        } else {
          key = CONTRACT_MAP[tx.contractName];
        }

        if (!key) continue;

        const addr = await toChecksumAddress(tx.contractAddress);
        if (!addresses[chainId]) addresses[chainId] = {};
        addresses[chainId][key] = addr;
      }
    }
  }

  // Sort chains numerically
  const sortedChains = Object.keys(addresses)
    .map(Number)
    .sort((a, b) => a - b);

  const lines: string[] = [
    `export type ContractAddresses = {`,
    `  yellowToken: \`0x\${string}\`;`,
    `  nodeRegistry: \`0x\${string}\`;`,
    `  appRegistry: \`0x\${string}\`;`,
    `  governor: \`0x\${string}\`;`,
    `  timelock: \`0x\${string}\`;`,
    ...Object.values(TREASURY_KEYS).map(
      (k) => `  ${k}: \`0x\${string}\`;`
    ),
    `  faucet?: \`0x\${string}\`;`,
    `};`,
    ``,
    `/**`,
    ` * Deployed contract addresses keyed by chain ID.`,
    ` *`,
    ` * Auto-generated from Forge broadcast artifacts — do not edit manually.`,
    ` */`,
    `export const addresses: Record<number, Partial<ContractAddresses>> = {`,
  ];

  for (const chainId of sortedChains) {
    const chain = CHAINS[chainId];
    lines.push(`  // ${chain.name}`);
    lines.push(`  ${chainId}: {`);

    const entries = Object.entries(addresses[chainId]).sort(
      ([a], [b]) => KEY_ORDER.indexOf(a) - KEY_ORDER.indexOf(b)
    );
    for (const [key, addr] of entries) {
      lines.push(`    ${key}: "${addr}",`);
    }

    lines.push(`  },`);
  }

  lines.push(`};`);
  lines.push(``);

  await writeFile(OUT_FILE, lines.join("\n"));
  console.log(
    `Extracted addresses for ${sortedChains.length} chain(s) to sdk/src/addresses.ts`
  );
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
