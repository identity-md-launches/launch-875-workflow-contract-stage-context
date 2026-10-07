// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {LaunchToken} from "src/LaunchToken.sol";
import {MossExperimentRegistry} from "src/MossExperimentRegistry.sol";

contract ModelExperiment {
    fallback() external {
        revert("catalog must not execute experiments");
    }
}

/// @dev Models the documented lifecycle using submitted inputs. No registry getter supplies
/// expected ids, contents, active pointers, or statuses. Failed operations leave the model alone.
contract RegistryModelHandler is Test {
    MossExperimentRegistry public immutable registry;
    address public immutable owner;
    address[3] public candidates;
    uint8[3] public codeVersion;
    uint256 public count;
    mapping(uint256 => MossExperimentRegistry.Proposal) private expected;
    mapping(bytes32 => uint256) public active;
    bytes32 private constant DECISION = keccak256("model review decision");

    constructor(MossExperimentRegistry registry_, address owner_) {
        registry = registry_;
        owner = owner_;
        for (uint256 i; i < 3; ++i) {
            candidates[i] = address(new ModelExperiment());
            codeVersion[i] = 1;
        }
    }

    function propose(uint8 actorSeed, uint8 keySeed, uint8 candidateSeed, bytes32 content) external {
        uint256 candidateIndex = candidateSeed % 3;
        address candidate = candidates[candidateIndex];
        bytes32 key = bytes32(uint256(keySeed % 4) + 1);
        address proposer = address(uint160(0xB100 + uint256(actorSeed % 4)));
        if (content == bytes32(0)) content = bytes32(uint256(1));
        if (codeVersion[candidateIndex] == 0) {
            vm.expectRevert(MossExperimentRegistry.InvalidImplementation.selector);
            vm.prank(proposer);
            registry.propose(key, candidate, content);
            return;
        }
        vm.prank(proposer);
        uint256 id = registry.propose(key, candidate, content);
        ++count;
        assertEq(id, count, "proposal ids must be contiguous");
        expected[count] = MossExperimentRegistry.Proposal({
            key: key,
            implementation: candidate,
            codeHash: keccak256(_runtime(codeVersion[candidateIndex])),
            contentHash: content,
            proposer: proposer,
            status: MossExperimentRegistry.Status.Pending
        });
    }

    /// @dev Includes unknown, finalized, stale, and changed-code approvals in random sequences.
    function approve(uint256 seed, bool stale) external {
        uint256 id = seed % (count + 2);
        MossExperimentRegistry.Proposal storage p = expected[id];
        uint256 previous = active[p.key];
        uint256 observed = stale ? previous ^ 1 : previous;
        bytes memory reason;
        if (id == 0 || id > count) {
            reason = abi.encodeWithSelector(MossExperimentRegistry.UnknownProposal.selector, id);
        } else if (p.status != MossExperimentRegistry.Status.Pending) {
            reason = abi.encodeWithSelector(MossExperimentRegistry.InvalidStatus.selector, id, p.status);
        } else if (stale) {
            reason = abi.encodeWithSelector(MossExperimentRegistry.StaleActiveProposal.selector, observed, previous);
        } else if (!_matches(p)) {
            reason = abi.encodeWithSelector(MossExperimentRegistry.ImplementationChanged.selector, id);
        }
        if (reason.length != 0) vm.expectRevert(reason);
        vm.prank(owner);
        registry.approve(id, observed, DECISION);
        if (reason.length == 0) {
            if (previous != 0) expected[previous].status = MossExperimentRegistry.Status.Retired;
            p.status = MossExperimentRegistry.Status.Active;
            active[p.key] = id;
        }
    }

    function reject(uint256 seed) external {
        uint256 id = seed % (count + 2);
        MossExperimentRegistry.Proposal storage p = expected[id];
        bool valid = id != 0 && id <= count && p.status == MossExperimentRegistry.Status.Pending;
        if (id == 0 || id > count) {
            vm.expectRevert(abi.encodeWithSelector(MossExperimentRegistry.UnknownProposal.selector, id));
        } else if (!valid) {
            vm.expectRevert(abi.encodeWithSelector(MossExperimentRegistry.InvalidStatus.selector, id, p.status));
        }
        vm.prank(owner);
        registry.reject(id, DECISION);
        if (valid) p.status = MossExperimentRegistry.Status.Rejected;
    }

    function retire(uint8 keySeed, bool stale) external {
        bytes32 key = bytes32(uint256(keySeed % 4) + 1);
        uint256 id = active[key];
        uint256 observed = stale ? id ^ 1 : id;
        if (id == 0) {
            vm.expectRevert(abi.encodeWithSelector(MossExperimentRegistry.NoActiveProposal.selector, key));
        } else if (stale) {
            vm.expectRevert(abi.encodeWithSelector(MossExperimentRegistry.StaleActiveProposal.selector, observed, id));
        }
        vm.prank(owner);
        registry.retire(key, observed, DECISION);
        if (id != 0 && !stale) {
            expected[id].status = MossExperimentRegistry.Status.Retired;
            active[key] = 0;
        }
    }

    /// @dev A controlled stand-in for direct runtime replacement/removal, not an exploit claim.
    /// Versions can be restored, allowing old and new proposals at the same address to disagree.
    function changeCode(uint8 candidateSeed, uint8 versionSeed) external {
        uint256 index = candidateSeed % 3;
        uint8 version = versionSeed % 3;
        vm.etch(candidates[index], _runtime(version));
        codeVersion[index] = version;
    }

    function unauthorized(uint256 seed, uint8 operation) external {
        uint256 id = seed % (count + 2);
        bytes32 key = bytes32(seed % 4 + 1);
        uint256 observed = active[key];
        vm.expectRevert(MossExperimentRegistry.Unauthorized.selector);
        vm.prank(address(0xBAD));
        if (operation % 3 == 0) registry.approve(id, observed, DECISION);
        else if (operation % 3 == 1) registry.reject(id, DECISION);
        else registry.retire(key, observed, DECISION);
    }

    function emptyDecision(uint256 seed, uint8 operation) external {
        uint256 id = seed % (count + 2);
        bytes32 key = bytes32(seed % 4 + 1);
        uint256 observed = active[key];
        vm.expectRevert(MossExperimentRegistry.EmptyHash.selector);
        vm.prank(owner);
        if (operation % 3 == 0) registry.approve(id, observed, bytes32(0));
        else if (operation % 3 == 1) registry.reject(id, bytes32(0));
        else registry.retire(key, observed, bytes32(0));
    }

    function assertModel() external view {
        assertEq(registry.proposalCount(), count, "unexpected proposal creation or deletion");
        for (uint256 id = 1; id <= count; ++id) {
            MossExperimentRegistry.Proposal memory actual = registry.getProposal(id);
            assertEq(keccak256(abi.encode(actual)), keccak256(abi.encode(expected[id])), "proposal differs from model");
            bool live = expected[id].status == MossExperimentRegistry.Status.Active && _matches(expected[id]);
            assertEq(registry.isActive(id), live, "endorsement must track current runtime");
        }
        for (uint256 key = 1; key <= 4; ++key) {
            assertEq(registry.activeProposal(bytes32(key)), active[bytes32(key)], "wrong active version");
        }
        assertFalse(registry.isActive(0));
        assertFalse(registry.isActive(count + 1));
    }

    function _matches(MossExperimentRegistry.Proposal storage p) private view returns (bool) {
        for (uint256 i; i < candidates.length; ++i) {
            if (p.implementation == candidates[i]) {
                return codeVersion[i] != 0 && p.codeHash == keccak256(_runtime(codeVersion[i]));
            }
        }
        revert("model refers to an untracked candidate");
    }

    function _runtime(uint8 version) private pure returns (bytes memory) {
        if (version == 0) return hex"";
        if (version == 1) return type(ModelExperiment).runtimeCode;
        return hex"600160005260206000f3";
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 96
/// forge-config: default.invariant.fail-on-revert = true
contract RegistryModelTest is Test {
    LaunchToken private token;
    MossExperimentRegistry private registry;
    RegistryModelHandler private handler;
    address private constant OWNER = address(0xA11CE);

    function setUp() public {
        token = new LaunchToken();
        registry = new MossExperimentRegistry(address(token), OWNER);
        handler = new RegistryModelHandler(registry, OWNER);

        // Each sequence starts with live, pending, rejected, and retired entries across keys.
        // This makes failed transitions meaningful even when the first random action is a decision.
        for (uint8 i; i < 4; ++i) {
            handler.propose(i, i, i % 3, bytes32(uint256(i) + 1));
        }
        handler.approve(1, false);
        handler.reject(2);
        handler.approve(3, false);
        handler.retire(2, false);
        handler.assertModel();

        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = handler.propose.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.reject.selector;
        selectors[3] = handler.retire.selector;
        selectors[4] = handler.changeCode.selector;
        selectors[5] = handler.unauthorized.selector;
        selectors[6] = handler.emptyDecision.selector;
        targetSelector(FuzzSelector(address(handler), selectors));
        targetContract(address(handler));
    }

    function invariant_exactHistoryAndCodeAwareEndorsements() public view {
        handler.assertModel();
        assertEq(registry.owner(), OWNER);
        assertEq(registry.token(), address(token));
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.balanceOf(address(this)), 1e27);
        assertEq(token.balanceOf(address(registry)), 0);
    }

    function test_modelExercisesReplacementRemovalRestorationAndFinality() public {
        handler.propose(1, 0, 1, bytes32(uint256(5)));
        handler.approve(5, true); // Stale competing review must leave proposal pending.
        handler.approve(5, false); // Retires proposal 1 and activates 5.
        handler.assertModel();
        handler.changeCode(1, 0);
        handler.propose(1, 0, 1, bytes32(uint256(6))); // Removed code cannot consume an id.
        handler.assertModel();
        handler.changeCode(1, 2);
        handler.propose(2, 0, 1, bytes32(uint256(6)));
        handler.changeCode(1, 1); // Original version restores 5 but invalidates pending 6.
        handler.approve(6, false);
        handler.assertModel();
        handler.changeCode(1, 2);
        handler.approve(6, false); // Changed old active code must not block replacement.
        handler.retire(0, false);
        handler.approve(1, false); // Finalized proposals cannot reopen, even with restored code.
        handler.approve(5, false);
        handler.reject(6);
        invariant_exactHistoryAndCodeAwareEndorsements();
    }
}
