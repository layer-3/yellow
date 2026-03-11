/**
 * Extracts ABIs from Foundry compilation artifacts (out/) and writes:
 *   1. Plain JSON files to sdk/abi/ (for direct consumption)
 *   2. Typed TypeScript re-exports to sdk/src/abi/ (as const for viem/wagmi)
 *
 * Usage: bun run script/extract-abis.ts
 */
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { join } from "node:path";
import { CONTRACTS } from "./contracts";

const ROOT = join(import.meta.dirname, "..");
const OUT_DIR = join(ROOT, "out");
const JSON_DIR = join(ROOT, "sdk", "abi");
const TS_DIR = join(ROOT, "sdk", "src", "abi");

async function main() {
  await mkdir(JSON_DIR, { recursive: true });
  await mkdir(TS_DIR, { recursive: true });

  const names: string[] = [];

  for (const [name, artifactPath] of Object.entries(CONTRACTS)) {
    const fullPath = join(OUT_DIR, artifactPath);
    const raw = await readFile(fullPath, "utf-8");
    const { abi } = JSON.parse(raw);

    // 1. Write plain JSON
    await writeFile(join(JSON_DIR, `${name}.json`), JSON.stringify(abi, null, 2) + "\n");

    // 2. Write typed TS that re-exports from JSON
    const ts = [
      `import abi from "../../abi/${name}.json";`,
      `export const ${name}Abi = abi as typeof abi;`,
      "",
    ].join("\n");
    await writeFile(join(TS_DIR, `${name}.ts`), ts);

    names.push(name);
    console.log(`  ${name} (${abi.length} entries)`);
  }

  // Write abi/index.ts barrel
  const barrel = names
    .map((n) => `export { ${n}Abi } from "./${n}";`)
    .join("\n") + "\n";
  await writeFile(join(TS_DIR, "index.ts"), barrel);

  console.log(`\nExtracted ${names.length} ABIs to sdk/abi/ and sdk/src/abi/`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
