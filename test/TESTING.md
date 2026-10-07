# Additional adversarial tests

These tests supplement the accepted suite without changing production contracts or configuration.

| File | Properties checked |
| --- | --- |
| `LaunchTokenModel.t.sol` | Four actors make independent transfers, approvals, revocations and delegated spends. Every balance and every actor/spender allowance must match the operation history; supply remains exactly `10^27`. Invalid transfers and spends must revert with the expected error and preserve the entire ledger. |
| `RegistryModel.t.sol` | Proposal ids, submitted contents, statuses and active pointers match a model constructed from call inputs. Random owner decisions, unauthorized calls, empty decisions and direct code changes must preserve immutable history and terminal states. Current runtime determines whether an endorsement is usable. |
| `LaunchTokenBoundaries.t.sol` | Delegated self-transfers conserve balances while consuming finite allowances. Zero, one unit, the full supply, maximum finite allowance and infinite allowance are pinned examples. Full-supply round trips and failed overspends preserve balances and approvals. |
| `RegistryAdversarial.t.sol` | Decisions for distinct keys commute; duplicate payloads retain separate histories; unknown ids cannot mutate existing proposals. Retirement invalidates an outstanding review expecting the retired id. Construction-time proposals and value-bearing lifecycle calls revert atomically. |

The two new invariant suites each declare 256 runs of depth 96 with failure on unexpected handler reverts. Target selectors include only the intended actions. Expected failures use exact custom errors, rather than catching arbitrary failures. The registry model starts with pending, active, retired and rejected entries. Deterministic sequence tests exercise replacement, runtime removal/restoration, finality, revocation and failed spending on every run. Expected proposal contents and token accounting are derived from submitted operations, not copied from contract getters.

The new stateless fuzz tests declare 1,000 runs in Solidity. Inputs are bounded or constructed directly, with no discarded assumptions. All dependencies are already vendored.

Reproduce offline:

```sh
forge build --offline
forge test --offline --fuzz-seed 0x7a11ce
forge test --offline --fuzz-seed 0xbadc0de --fuzz-runs 2000
forge fmt --check
```

Inline run counts remain effective when the verifier runs plain `forge test`. The extra command-line fuzz count is only a local stress check for tests without an inline override.

`vm.etch` changes only local experiment fixtures to exercise the documented direct-runtime checks. These simulations do not establish that code replacement is possible on the deployment chain, and do not claim to detect proxy or dependency changes. There are no forks, external protocol integrations, network reads, environment mutations, or deployment actions in these additions. The service-provided protected checks remain separate inputs; these tests do not depend on them.
