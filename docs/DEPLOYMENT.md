# Deployment handoff

This is source-assignment guidance, not `launch.json`. The manifest contributor produces the canonical manifest from accepted artifacts and policy; an independent reviewer examines it with the source.

## Artifact order and constructor arguments

| Order | Identifier | Source | Constructor | Value |
| --- | --- | --- | --- | --- |
| Token | `LaunchToken` | `src/LaunchToken.sol` | none | `0` |
| Application 1 | `MossExperimentRegistry` | `src/MossExperimentRegistry.sol` | `address token_ = $token`, `address owner_ = $owner` | `0` |

Both identifiers fit the 32-character ASCII limit. The application references the already deployed token. The owner must be nonzero and different from the deploying factory, token, and registry address. The constructor checks token code presence; correct token identity is established by the manifest's `$token` reference and independent review, not by ERC-20 interface probing.

`LaunchToken` has 18 decimals and supply `1000000000000000000000000000`. Its name and symbol are both case-sensitive `Moss`. No post-deployment call is needed. The application constructor makes no external call and does not move supply.

Compiler: `0.8.26`; optimizer: enabled, 200 runs; EVM: `paris`; bytecode hash: `none`. Build settings are in `foundry.toml`. ABIs are in `docs/abi/LaunchToken.json` and `docs/abi/MossExperimentRegistry.json`. No library linking is required.

## Canonical launch inputs

- Kind: `evm_project`, one application in dependency order. No contributor implementation/listing of `MerkleDistributor` or `PoolInitializationGuard`.
- Pair currency: native ETH (zero address), since the brief provides no pair-token choice. Network/policy must confirm it at admission.
- Admission pool settings: fee `3000`, tick spacing `60`, initial price `79228162514264337593543950336`. The policy opening cap determines the effective opening price for current policies.
- Pool trading fees come from the network's `LaunchFees`, not from the admission fee field; the supplied guidance describes a default 1.25%, split 1% to the launch payer and 0.25% to IMD. The launch service must use the pinned policy and actual deployment handoff.
- The factory distributes the supply and seeds token-only liquidity. No application receives launch tokens during construction.

## Operational responsibilities

| Responsible party | Required work |
| --- | --- |
| Manifest assignment | Resolve source identifiers and constructor references; produce only `launch.json`. |
| Independent reviewer | Inspect final source and manifest, owner authorization, factory/owner separation, supply, and the hook-concept conflict in `REVIEW-NOTES.md`. |
| Publication/attestation services | Publish accepted source, bind compiled artifacts to policy, attest and admit. Signed artifact linkage and publication policy are service responsibilities. |
| Deployment service | Obtain authoritative Robinhood network/factory/owner values, verify EVM support and protocol addresses, deploy accepted bytes, check runtime and roles, and publish exact addresses and poolKey. No values in historical reference tables have been adopted here. |
| Owner | Control the policy-selected registry owner address; review proposals before endorsing them; publish decision documents. Registry authority has no timelock and cannot be transferred by this contract. |
| Research/journal operator | Research ideas offchain, publish exact document bytes to IPFS, retain/pin historical documents, submit proposals, and preserve decision document availability. This role receives no registry privilege. |
| Frontend service | Host on IPFS, use deployment handoff addresses/poolKey, show provenance and proposal status, verify document hashes, distinguish endorsement from execution, and expose history. |

Documents are located through an offchain index keyed by `contentHash`/`decisionHash`; the hashes are not full IPFS CIDs. Publication and pinning must complete before an endorsement is presented to users. Index logs from registry deployment and allow for chain reorganizations. Direct runtime hashes are a consistency check, not a substitute for module/dependency review.

The new registry begins empty. No particular experiment, prediction market, trading strategy, buyback, fee splitter, or AI process is deployed by this assignment. Any future implementation is a separately scoped contract deployment and review. Registering it here does not add it to the protocol pool.
