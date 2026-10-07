# Source author review notes

These are implementation notes for the independent reviewer, not an independent review or a claim of launch approval.

## Concrete concept/policy conflict

The linked concept uses replaceable Uniswap v4 hook logic. This project's launch route supplies an initialization-only protocol guard, prohibits proxies/delegatecall, and requires a plain, immutable launch token. Consequently this implementation delivers an owner-approved experiment catalog and public history, **not replaceable swap callbacks or arbitrary execution**. The independent reviewer should retain this product limitation as a source/requirements finding. Do not describe registry approval as enabling a trading mechanic. A full replication requires a separately approved architecture compatible with launch policy.

No particular future experiment is specified in the brief. The catalog is empty on launch; the only deployed functionality is the token and proposal/approval lifecycle. Research, AI autonomy, social replies, document hosting, and future experiment code are external responsibilities.

## Privileged role

`MossExperimentRegistry.owner` is the immutable explicit constructor argument `$owner`, not the factory's `msg.sender`. Constructor validation rejects the factory as owner. Only that address can approve/reject/retire. There is no transfer-of-ownership, pause, upgrade, timelock, or emergency execution. Review the concrete manifest owner before launch; a wrong valid address cannot be repaired in this contract. A controlled multisig is recommended operationally, but the manifest must resolve the policy's authorized owner.

The owner may endorse malicious experiments immediately. Permissionless proposers may submit malicious or duplicate entries. Neither can cause registry execution, siphon launch supply, or change token behavior. Frontends must distinguish pending suggestions from owner endorsements and separately assess each external contract.

## Code and custody assumptions

- All project entry points are nonpayable. The registry makes no external calls, so there is no callback/reentrancy path in its lifecycle. Tests register a contract whose fallback always reverts and still complete approval/replacement operations.
- Proposal runtime hashes catch direct code replacement/removal at approval and through `isActive`. They cannot prove that a listed contract lacks a proxy, mutable dependency, admin power, or unsafe implementation. Review every external experiment separately. The catalog itself cannot enforce the full launch opcode policy on future external contracts.
- If code changes after endorsement, `activeProposal` retains the historical endorsement id while `isActive` returns false. The owner can still retire or replace it. Consumers must use both views.
- Stale approval/retirement protection compares the expected currently active id. Each proposal can be activated once; older finalized entries cannot be revived. Multiple independent experiment keys can coexist.
- Identical proposal payloads are allowed. Ids are globally unique, keys are not reserved by proposers, and core operations have no unbounded loops. Applications should filter spam offchain.
- The token never calls recipients. Transfers conserve total supply. Standard allowances remain user-controlled, including ERC-20 maximum allowances.
- No rescue path is provided. Accidental token transfers and forced ETH are unrecoverable. No user funds are required for any registry operation beyond network gas.
- No timing, randomness, oracle, chain id, stock token, bridge, pool-manager address, or historical RPC assumption is embedded in contract code.

## Validation and remaining review

Project tests cover factory CREATE2 prediction/constructor execution, full supply preservation, EIP-170 size and forbidden runtime opcodes, ERC-20 success/failure behavior, administrative selector rejection, registry lifecycle and events, unauthorized callers, stale actions, changed code, and immutable history. Stateful tests exercise transfers, allowances, proposals, approvals, rejections, and retirements, checking supply and history after generated sequences.

Run records are local engineering evidence only. The supplied protected harness is not copied into the delivered suite; it requires service-populated deployment inputs and is run independently by verification. No Slither/Mythril audit, live-chain deployment, transaction broadcast, or independent source-and-manifest review has been performed here.

The manifest remains a separate assignment. Missing service-signed artifact linkage, publication, attestation, admission, deployment, and frontend hosting are service responsibilities, not source defects or prerequisites. Concrete source, constructor, owner, or policy conflicts remain review findings.
