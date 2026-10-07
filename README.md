# Moss

Moss is a fixed-supply ERC-20 and a public, owner-curated catalog of experiments around that same token. This repository delivers the contract stage: implementation, tests, ABI exports, and a deployment/review handoff.

The approved brief names **Moss**, symbol **Moss**, and requests the concept from [Founder Claus's October 4 article](https://x.com/founderclaus/status/2106873130191041017) on Robinhood Chain. The article describes evolving experiments around one token, visible history, and human approval of onchain changes. Its text was retrieved through [the post's public mirror](https://api.fxtwitter.com/founderclaus/status/2106873130191041017) because the direct X page returned 403.

**Scope assumption:** this implementation provides the compatible token and experiment catalog. It does **not** reproduce replaceable Uniswap swap hooks. The launch requirements specify an initialization-only protocol guard and prohibit proxies, delegatecall, custom token fees, and token upgrades. The catalog cannot change swap rules or execute experiments. This concrete difference from the linked concept is recorded in [review notes](docs/REVIEW-NOTES.md).

## Delivered contracts

| Contract | Behavior |
| --- | --- |
| `LaunchToken` | Name/symbol `Moss`/`Moss`, 18 decimals, exactly 1,000,000,000 tokens (`10^27` minor units), all minted to the constructor caller. Standard transfers and allowances. |
| `MossExperimentRegistry` | Associates an immutable token with permissionless experiment proposals and explicit owner approval, replacement, rejection, and retirement. Original proposal contents and decision events preserve history. |

The token has no owner, mint entry point, burn entry point, pause, blocklist, transfer fee, hooks, or upgrade mechanism. Registry ownership grants no power over token balances or supply. The registry handles no deposits, spending, rewards, swaps, randomness, or user approvals. AI research, social interaction, execution of independent experiments, and publication of journal documents are external operations.

## Build and check

Requires Foundry and the pinned Solidity **0.8.26** compiler. All Solidity dependencies are vendored as ordinary files with licenses; no package installation or network fetch is needed once that compiler is installed. The verifier supplies the compiler. Python 3 is used only to export/check ABI files.

```sh
forge build
forge test
forge fmt --check
python3 scripts/export_abis.py --check
```

Regenerate ABIs after a source change with `python3 scripts/export_abis.py`. Configuration uses `bytecode_hash = "none"`, optimizer 200 runs, and the conservative `paris` EVM target. FFI and Solidity test filesystem access are disabled. There are no RPC calls, forks, private keys, environment reads, or environment mutations in project tests. The suite is independent of test order and shared environment state.

OpenZeppelin Contracts **v5.1.0** supplies the unchanged ERC-20 implementation; forge-std **v1.9.4** supplies test utilities. [Dependency provenance and SHA-256 hashes](docs/dependencies.json) cover every vendored file. Dependencies are not submodules.

## Experiment lifecycle

1. An operator publishes and pins a UTF-8 journal document describing a separately deployed experiment. Compute `keccak256` over the exact document bytes. No onchain contract fetches this document.
2. Anyone can call `propose(key, implementation, contentHash)`. `key` is a nonzero, stable experiment identifier, typically the hash of an agreed name. The implementation must already have code. A proposal records the caller, address, direct runtime hash, and document hash. Proposal ids start at 1.
3. The policy owner reviews the implementation, dependencies, and published document, then calls `approve(id, expectedActiveId, decisionHash)`. The implementation's direct runtime must still match. `expectedActiveId` must equal the currently endorsed id for that key, including zero if none is active.
4. Approval retires any previous version for that key. Different keys can remain active simultaneously. The owner can instead reject a pending proposal or retire an active version with a published decision hash. Retired and rejected entries are final; another endorsement requires a new proposal.
5. The frontend displays approved entries using `activeProposal(key)` **and** `isActive(id)`, and reconstructs journal decisions from events. Users interact with separately reviewed experiments directly and opt in to their risks. Registry approval does not execute code or authorize token spending.

All transitions are constant cost with no growing-list iteration. Permissionless submissions can contain duplicates or misleading claims; only the owner can endorse them. Submitting first never reserves a key. Do not render pending entries as official Moss functionality.

## Deployment and operations

Deploy `LaunchToken()` first, then `MossExperimentRegistry($token, $owner)` through the launch factory. Both constructors are nonpayable and fully configure their contracts; no initialization calls are required. The explicit registry owner must be separate from the factory, token, registry itself, and zero address. A policy-selected multisig can rotate its signers without changing the registry's immutable owner address.

No authoritative `network.json`, policy owner, factory address, chain id, or RPC endpoint was supplied. These values must come from the launch service's pinned network and policy. The implementation embeds no chain addresses and makes no claims that Robinhood infrastructure has been verified. EVM compatibility and the actual deployment network remain service checks; this assignment makes no transactions.

The factory performs the policy distribution: 10% to network contributors/seats and the remaining 90% to the requester, split between liquidity and their wallet per policy (default 80% of total supply for liquidity). Neither delivered contract distributes or reserves launch supply. The protocol supplies the pool, distributor, and initialization guard. Pool trading fees are network controlled; the token and registry charge none. Do not describe the admission field `fee = 3000` as the live trading fee.

See [deployment handoff](docs/DEPLOYMENT.md), [ABI documentation](docs/ABI.md), and [review notes](docs/REVIEW-NOTES.md). The separate manifest assignment owns `launch.json`; services publish source, attest, admit, deploy, and start the IPFS frontend afterward. Those service results are not prerequisites of this source assignment.

The owner controls endorsements immediately, with no built-in timelock or token-holder vote. Losing control of that address freezes future decisions. Owner compromise can endorse malicious external contracts, but the registry still cannot execute them or move holders' funds. Runtime-hash checks do not detect proxy implementation changes, mutable dependencies, or unsafe logic. Each future experiment needs its own review. Never send tokens or ETH to the registry: accidental ERC-20 transfers or forcibly delivered ETH cannot be recovered.

Local tests include transfers and allowances, invalid operations, unauthorized decisions, stale approvals, changed code, history preservation, factory construction, forbidden runtime opcodes, and stateful conservation/registry invariants. These checks are not an independent security audit. The independent source-and-manifest review is a separate stage.
