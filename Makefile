-include .env

# Build & Compile
build:
	forge build

clean:
	forge clean

# Code Quality
fmt:
	forge fmt

fmt-check:
	forge fmt --check

lint:
	forge lint

# Testing
test:
	forge test

test-v:
	forge test -vvv

test-vv:
	forge test -vvvv

test-token:
	forge test --match-path test/Token.t.sol -vvv

test-faucet:
	forge test --match-path test/Faucet.t.sol -vvv

test-locker:
	forge test --match-path test/Locker.t.sol -vvv

test-node-registry:
	forge test --match-path test/NodeRegistry.t.sol -vvv

test-app-registry:
	forge test --match-path test/AppRegistry.t.sol -vvv

test-governor:
	forge test --match-path test/Governor.t.sol -vvv

# Gas
snapshot:
	forge snapshot

gas-report:
	forge test --gas-report

# Coverage
coverage:
	forge coverage

coverage-report:
	forge coverage --report lcov

# Deploy Scripts
deploy-token-sepolia:
	forge script script/DeployToken.s.sol --rpc-url sepolia --broadcast --verify

deploy-token-mainnet:
	forge script script/DeployToken.s.sol --rpc-url mainnet --broadcast --verify

deploy-faucet-sepolia:
	forge script script/DeployFaucet.s.sol --rpc-url sepolia --broadcast --verify

deploy-faucet-mainnet:
	forge script script/DeployFaucet.s.sol --rpc-url mainnet --broadcast --verify

deploy-registry-sepolia:
	forge script script/DeployRegistry.s.sol --rpc-url sepolia --broadcast --verify

deploy-registry-mainnet:
	forge script script/DeployRegistry.s.sol --rpc-url mainnet --broadcast --verify

deploy-treasury-sepolia:
	forge script script/DeployTreasury.s.sol --rpc-url sepolia --broadcast --verify

deploy-treasury-mainnet:
	forge script script/DeployTreasury.s.sol --rpc-url mainnet --broadcast --verify

# SDK
sdk-build:
	cd sdk && bun install && bun run build

sdk-lint:
	cd sdk && bun run lint

sdk-lint-fix:
	cd sdk && bun run lint:fix

sdk-extract:
	bun run script/extract-abis.ts
	bun run script/extract-addresses.ts

# Docs
docs:
	bun run script/build-docs.ts

# Release — usage: make release [v=1.2.3]
# Defaults to patch bump if v is not specified.
release:
	$(eval v := $(or $(v),$(shell cd sdk && bun -e "const s=require('./package.json').version.split('.');s[2]=+s[2]+1;console.log(s.join('.'))")))
	@echo "==> Releasing v$(v)"
	@echo "==> Running checks..."
	forge fmt --check
	forge test -vvv
	cd sdk && bun run lint
	@echo "==> Updating sdk/package.json version to $(v)..."
	cd sdk && npm version "$(v)" --no-git-tag-version
	@echo "==> Building SDK..."
	$(MAKE) sdk-build
	@echo "==> Running SDK tests..."
	cd sdk && bun test
	@echo "==> Building docs..."
	$(MAKE) docs
	@echo "==> Committing generated files..."
	git add docs/ sdk/package.json sdk/README.md
	git diff --cached --quiet || git commit -m "chore: release v$(v)"
	@echo "==> Tagging v$(v)..."
	git tag -a "v$(v)" -m "Release v$(v)"
	@echo ""
	@echo "Release v$(v) tagged. Push to publish:"
	@echo "  git push origin master --tags"

# Dependencies
install:
	forge install

update:
	forge update

# Misc
sizes:
	forge build --sizes

.PHONY: build clean fmt fmt-check lint test test-v test-vv \
	test-token test-faucet test-locker test-node-registry test-app-registry test-governor \
	snapshot gas-report coverage coverage-report \
	deploy-token-sepolia deploy-token-mainnet \
	deploy-faucet-sepolia deploy-faucet-mainnet \
	deploy-registry-sepolia deploy-registry-mainnet \
	deploy-treasury-sepolia deploy-treasury-mainnet \
	sdk-build sdk-lint sdk-lint-fix sdk-extract docs release \
	install update sizes
