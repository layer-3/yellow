/**
 * Extracts ABIs from Foundry compilation artifacts (out/) and writes them
 * as `as const` TypeScript files into sdk/src/abi/.
 *
 * Usage: bun run script/extract-abis.ts
 */
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { join } from "node:path";
import { CONTRACTS } from "./contracts";

const ROOT = join(import.meta.dirname, "..");
const OUT_DIR = join(ROOT, "out");
const ABI_DIR = join(ROOT, "sdk", "src", "abi");

async function main() {
  await mkdir(ABI_DIR, { recursive: true });

  const names: string[] = [];

  for (const [name, artifactPath] of Object.entries(CONTRACTS)) {
    const fullPath = join(OUT_DIR, artifactPath);
    const raw = await readFile(fullPath, "utf-8");
    const { abi } = JSON.parse(raw);

    const content = [
      `export const ${name}Abi = ${JSON.stringify(abi, null, 2)} as const;`,
      "",
    ].join("\n");

    await writeFile(join(ABI_DIR, `${name}.ts`), content);
    names.push(name);
    console.log(`  ${name} (${abi.length} entries)`);
  }

  // Write abi/index.ts barrel
  const barrel = names
    .map((n) => `export { ${n}Abi } from "./${n}";`)
    .join("\n") + "\n";
  await writeFile(join(ABI_DIR, "index.ts"), barrel);

  console.log(`\nExtracted ${names.length} ABIs to sdk/src/abi/`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
