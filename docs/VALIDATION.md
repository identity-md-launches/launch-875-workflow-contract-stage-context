# Local validation record

Checked on 2026-10-07 with Foundry 1.8.3 and Solidity 0.8.26, using the committed compiler settings.

| Check | Result |
| --- | --- |
| `forge build` | Pass, no compiler warnings. |
| `forge test` | 42 tests reported passing; 0 failures and 0 skips. |
| `forge fmt --check` | Pass. |
| `python3 scripts/export_abis.py --check` | Both exported ABIs match compiler output. |
| Vendored-file SHA-256 checks | All 34 dependency files match `docs/dependencies.json`; no symlinks. |
| Fresh-copy `forge build --offline` and `forge test --offline` | Pass after copying only project files/dependencies, without build caches, pinned inputs, or scratch tests. |

The suite comprises 16 token tests, 22 registry tests, 3 factory/deployment tests, and one stateful suite checking two invariants. Four fuzz tests use 256 cases each. The stateful suite uses 128 runs of depth 64 (8,192 calls), with zero handler reverts, checking conservation of token supply/balances and consistency of immutable proposal contents, terminal states, and active pointers.

Runtime sizes reported by `forge build --sizes`: `LaunchToken` 1,784 bytes; `MossExperimentRegistry` 2,844 bytes. Both are below EIP-170's 24,576-byte limit. Project tests also scan deployed runtime for forbidden DELEGATECALL, CALLCODE, and SELFDESTRUCT instructions while skipping PUSH data.

The clean offline run retained only the host's unchanged `HOME` setting and no project environment variables. A literally empty process environment caused Foundry's compiler manager to crash before compilation because it could not locate the user home directory. This is a host-toolchain requirement; project tests neither read nor set environment variables.

These are source-author checks, not independent audit/acceptance evidence. Service-populated protected tests, final manifest review, and deployment verification remain separate steps. No live-chain calls or deployments were made.
