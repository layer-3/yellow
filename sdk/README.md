# @yellow-org/contracts

Typed ABIs and deployed addresses for all Yellow Network smart contracts. Works with viem, ethers.js, wagmi, or any EVM library.

## Install

```bash
npm install @yellow-org/contracts
```

```bash
yarn add @yellow-org/contracts
```

```bash
pnpm add @yellow-org/contracts
```

```bash
bun add @yellow-org/contracts
```

## Usage

### viem

```ts
import { createPublicClient, http } from "viem";
import { mainnet } from "viem/chains";
import { NodeRegistryAbi, addresses } from "@yellow-org/contracts";

const client = createPublicClient({
  chain: mainnet,
  transport: http(),
});

// Read a node operator's locked collateral — fully typed
const balance = await client.readContract({
  address: addresses[1].nodeRegistry!,
  abi: NodeRegistryAbi,
  functionName: "balanceOf",
  args: ["0x..."],
});
```

### ethers v6

```ts
import { Contract, JsonRpcProvider } from "ethers";
import { NodeRegistryAbi, addresses } from "@yellow-org/contracts";

const provider = new JsonRpcProvider("https://eth.llamarpc.com");

const nodeRegistry = new Contract(
  addresses[1].nodeRegistry!,
  NodeRegistryAbi,
  provider
);

const balance = await nodeRegistry.balanceOf("0x...");
```

### wagmi (React)

```ts
import { useReadContract } from "wagmi";
import { NodeRegistryAbi, addresses } from "@yellow-org/contracts";

function LockedCollateral({ user }: { user: `0x${string}` }) {
  const { data: balance } = useReadContract({
    address: addresses[1].nodeRegistry!,
    abi: NodeRegistryAbi,
    functionName: "balanceOf",
    args: [user],
  });

  return <span>{balance?.toString()} YELLOW</span>;
}
```

## Exports

### ABIs

```ts
import {
  YellowTokenAbi,
  NodeRegistryAbi,
  AppRegistryAbi,
  YellowGovernorAbi,
  TimelockControllerAbi,
  TreasuryAbi,
  FaucetAbi,
  ILockAbi,
  ISlashAbi,
} from "@yellow-org/contracts";
```

| Export | Contract | Description |
|---|---|---|
| `YellowTokenAbi` | YellowToken | ERC-20 + EIP-2612 permit |
| `NodeRegistryAbi` | NodeRegistry | Node operator collateral (ILock + IVotes) |
| `AppRegistryAbi` | AppRegistry | App builder collateral + slashing (ILock + ISlash) |
| `YellowGovernorAbi` | YellowGovernor | Protocol parameter administration |
| `TimelockControllerAbi` | TimelockController | Delayed execution |
| `TreasuryAbi` | Treasury | Foundation vault |
| `FaucetAbi` | Faucet | Testnet faucet |
| `ILockAbi` | ILock | Lock/unlock interface (shared by both registries) |
| `ISlashAbi` | ISlash | Slash interface |

All ABIs are exported as `as const` arrays for full type inference with viem and wagmi.

### Addresses

```ts
import { addresses, type ContractAddresses } from "@yellow-org/contracts";

addresses[1]         // Ethereum Mainnet
addresses[11155111]  // Sepolia Testnet
```

### Generic registry code

Use `ILockAbi` to write code that works with both NodeRegistry and AppRegistry:

```ts
import { ILockAbi } from "@yellow-org/contracts";

const balance = await client.readContract({
  address: registryAddress,
  abi: ILockAbi,
  functionName: "balanceOf",
  args: [userAddress],
});
```

## Deployed Addresses

### Ethereum Mainnet (Chain ID: 1)

| Contract | Address |
|---|---|
| YellowToken | `0x236eB848C95b231299B4AA9f56c73D6893462720` |

### Sepolia Testnet (Chain ID: 11155111)

| Contract | Address |
|---|---|
| YellowToken | `0x236eB848C95b231299B4AA9f56c73D6893462720` |
| Faucet | `0x914abaDC0e36e03f29e4F1516951125c774dBAc8` |

## License

GPL-3.0-or-later
