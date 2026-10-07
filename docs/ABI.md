# Contract ABI documentation

The JSON files under `docs/abi/` are complete compiler-generated ABI arrays, including constructors, errors, and events. Regenerate with `python3 scripts/export_abis.py`; verify exact agreement with `python3 scripts/export_abis.py --check`. Run from a checkout containing the vendored dependencies and Solidity 0.8.26.

## LaunchToken

Constructor: `constructor()` (nonpayable). Mints `10^27` minor units to `msg.sender`.

| Function | Result/behavior |
| --- | --- |
| `name()`, `symbol()` | Both return `Moss`. |
| `decimals()` | Returns `18`. |
| `totalSupply()` | Returns constant lifetime supply `10^27`. |
| `balanceOf(address)` | Current balance in minor units. |
| `allowance(address,address)` | Current delegated spending limit in minor units. |
| `transfer(address,uint256)` | Caller transfers exact value; returns true or reverts. |
| `approve(address,uint256)` | Replaces spender allowance; returns true or reverts. |
| `transferFrom(address,address,uint256)` | Spends caller's allowance and transfers exact value; returns true or reverts. Maximum uint256 allowance remains unchanged. |

Standard `Transfer` and `Approval` events and ERC-6093 custom errors are included in the ABI. No `Approval` event is emitted when `transferFrom` reduces allowance, as in OpenZeppelin v5.1. Zero-value transfers are permitted; zero recipients/spenders are rejected. No payable methods, fallback, or receive handler exist. Use limited allowances; changing a nonzero allowance has ordinary ERC-20 transaction-ordering semantics.

## MossExperimentRegistry

Constructor: `constructor(address token_, address owner_)` (nonpayable).

| Function | Access | Meaning |
| --- | --- | --- |
| `token()`, `owner()` | Public view | Immutable token/curator addresses. |
| `proposalCount()` | Public view | Last allocated id; zero initially. |
| `activeProposal(bytes32 key)` | Public view | Endorsed, unretired id, or zero. Does not validate current implementation code. |
| `getProposal(uint256 id)` | Public view | Returns `(key, implementation, codeHash, contentHash, proposer, status)`; unknown ids revert. |
| `isActive(uint256 id)` | Public view | True if id is endorsed for its key and direct runtime still matches; unknown ids return false. |
| `propose(bytes32 key,address implementation,bytes32 contentHash)` | Anyone | Creates a pending entry, returns its id. |
| `approve(uint256 id,uint256 expectedActiveId,bytes32 decisionHash)` | Owner | Activates a pending version and retires the previous version, atomically. |
| `reject(uint256 id,bytes32 decisionHash)` | Owner | Finalizes a pending entry as rejected. |
| `retire(bytes32 key,uint256 expectedActiveId,bytes32 decisionHash)` | Owner | Finalizes the active entry as retired and clears its active pointer. |

Status encoding: `0=None`, `1=Pending`, `2=Active`, `3=Retired`, `4=Rejected`. Valid state transitions are Pending → Active/Rejected and Active → Retired. `None` is only an unallocated mapping value. The payload stays unchanged throughout every transition. Proposals do not expire.

Events:

- `ExperimentProposed`: indexed id, key, proposer; implementation, code hash, content hash.
- `ExperimentApproved`: indexed id and key; previous id and decision hash.
- `ExperimentRetired`: indexed id and key; decision hash. Also emitted before approval when replacing an active version.
- `ExperimentRejected`: indexed id and key; decision hash.

Decision hashes live in events, so a complete journal requires log indexing. The hashes are `keccak256` commitments to exact UTF-8 document bytes, including whitespace/newlines. Choose one serialization before hashing. An experiment document should identify the network, token, registry, key, implementation, runtime hash, source, behavior, permissions, risks, and tests. A decision document should identify the proposal id, intended action, reviewer, and rationale. These fields are an operator convention; the contract only requires nonzero digests.

Errors distinguish bad constructor values (`InvalidOwner`, `InvalidToken`), empty identifiers/documents (`EmptyHash`), non-contract/token/self candidates (`InvalidImplementation`), absent ids (`UnknownProposal`), wrong lifecycle state (`InvalidStatus`), outdated expectations (`StaleActiveProposal`), changed/missing runtime (`ImplementationChanged`), absent active entries (`NoActiveProposal`), and missing owner authorization (`Unauthorized`). Reverts leave proposals, pointers, and the token unchanged.

No method executes the implementation or pays it, and no method moves ETH or ERC-20s. A module's interface is its own separately reviewed ABI. An endorsement cannot be used as an approval to spend the user's tokens.
