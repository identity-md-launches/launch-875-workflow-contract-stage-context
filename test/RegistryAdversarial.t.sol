// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {LaunchToken} from "src/LaunchToken.sol";
import {MossExperimentRegistry} from "src/MossExperimentRegistry.sol";

contract RecordingExperiment {
    uint256 public calls;

    fallback() external {
        ++calls;
    }
}

contract PrematureExperiment {
    constructor(MossExperimentRegistry registry) {
        registry.propose(bytes32(uint256(1)), address(this), bytes32(uint256(2)));
    }
}

/// forge-config: default.fuzz.runs = 1000
contract RegistryAdversarialTest is Test {
    LaunchToken private token;
    MossExperimentRegistry private registry;
    RecordingExperiment private candidate;
    address private constant OWNER = address(0xA11CE);
    bytes32 private constant KEY = keccak256("experiment");
    bytes32 private constant CONTENT = keccak256("journal");
    bytes32 private constant DECISION = keccak256("review");

    function setUp() public {
        token = new LaunchToken();
        registry = new MossExperimentRegistry(address(token), OWNER);
        candidate = new RecordingExperiment();
    }

    function testFuzz_independentKeyDecisionsCommute(bytes32 keyA, bytes32 keyB, bool retireA, bool rejectB) public {
        keyA = _nonzero(keyA);
        keyB = _nonzero(keyB);
        if (keyB == keyA) keyB = keyA == bytes32(uint256(1)) ? bytes32(uint256(2)) : bytes32(uint256(1));
        MossExperimentRegistry other = new MossExperimentRegistry(address(token), OWNER);
        _seedTwoKeys(registry, keyA, keyB);
        _seedTwoKeys(other, keyA, keyB);

        vm.startPrank(OWNER);
        _decideA(registry, keyA, retireA);
        _decideB(registry, rejectB);
        _decideB(other, rejectB);
        _decideA(other, keyA, retireA);
        vm.stopPrank();

        assertEq(registry.proposalCount(), 4);
        assertEq(other.proposalCount(), 4);
        assertEq(registry.activeProposal(keyA), retireA ? 0 : 3);
        assertEq(registry.activeProposal(keyB), rejectB ? 2 : 4);
        assertEq(other.activeProposal(keyA), registry.activeProposal(keyA));
        assertEq(other.activeProposal(keyB), registry.activeProposal(keyB));
        for (uint256 id = 1; id <= 4; ++id) {
            assertEq(keccak256(abi.encode(registry.getProposal(id))), keccak256(abi.encode(other.getProposal(id))));
            assertEq(registry.isActive(id), other.isActive(id));
        }
        assertEq(candidate.calls(), 0, "even successful callbacks must never be invoked");
    }

    function testFuzz_duplicatePayloadsPreserveIndependentHistory(bytes32 key, bytes32 content, bytes32 decision)
        public
    {
        key = _nonzero(key);
        content = _nonzero(content);
        decision = _nonzero(decision);
        uint256 first = registry.propose(key, address(candidate), content);
        uint256 second = registry.propose(key, address(candidate), content);
        assertEq(first, 1);
        assertEq(second, 2);
        MossExperimentRegistry.Proposal memory original = MossExperimentRegistry.Proposal({
            key: key,
            implementation: address(candidate),
            codeHash: address(candidate).codehash,
            contentHash: content,
            proposer: address(this),
            status: MossExperimentRegistry.Status.Pending
        });
        assertEq(keccak256(abi.encode(registry.getProposal(first))), keccak256(abi.encode(original)));
        vm.startPrank(OWNER);
        registry.approve(second, 0, decision);
        registry.reject(first, decision);
        vm.stopPrank();
        original.status = MossExperimentRegistry.Status.Rejected;
        assertEq(keccak256(abi.encode(registry.getProposal(first))), keccak256(abi.encode(original)));
        original.status = MossExperimentRegistry.Status.Active;
        assertEq(keccak256(abi.encode(registry.getProposal(second))), keccak256(abi.encode(original)));
        assertTrue(registry.isActive(second));
        assertFalse(registry.isActive(first));
        assertEq(registry.activeProposal(key), second);
        assertEq(candidate.calls(), 0);
    }

    function testFuzz_unknownIdsCannotAffectExistingHistory(uint256 unknown) public {
        uint256 id = registry.propose(KEY, address(candidate), CONTENT);
        vm.prank(OWNER);
        registry.approve(id, 0, DECISION);
        bytes32 before = keccak256(abi.encode(registry.getProposal(id)));
        unknown = bound(unknown, 2, type(uint256).max);
        bytes memory reason = abi.encodeWithSelector(MossExperimentRegistry.UnknownProposal.selector, unknown);
        vm.expectRevert(reason);
        registry.getProposal(unknown);
        vm.startPrank(OWNER);
        vm.expectRevert(reason);
        registry.approve(unknown, id, DECISION);
        vm.expectRevert(reason);
        registry.reject(unknown, DECISION);
        vm.stopPrank();
        assertFalse(registry.isActive(unknown));
        assertEq(registry.proposalCount(), 1);
        assertEq(registry.activeProposal(KEY), id);
        assertEq(keccak256(abi.encode(registry.getProposal(id))), before);
    }

    function test_retirementInvalidatesAnOutstandingReplacementReview() public {
        uint256 first = registry.propose(KEY, address(candidate), CONTENT);
        uint256 second = registry.propose(KEY, address(candidate), CONTENT);
        vm.startPrank(OWNER);
        registry.approve(first, 0, DECISION);
        registry.retire(KEY, first, DECISION);
        vm.expectRevert(abi.encodeWithSelector(MossExperimentRegistry.StaleActiveProposal.selector, first, 0));
        registry.approve(second, first, DECISION);
        assertEq(uint8(registry.getProposal(second).status), uint8(MossExperimentRegistry.Status.Pending));
        registry.approve(second, 0, DECISION);
        vm.stopPrank();
        assertTrue(registry.isActive(second));
        assertFalse(registry.isActive(first));
    }

    function test_contractUnderConstructionCannotBeRegistered() public {
        vm.expectRevert(MossExperimentRegistry.InvalidImplementation.selector);
        new PrematureExperiment(registry);
        assertEq(registry.proposalCount(), 0);
        assertEq(registry.propose(KEY, address(candidate), CONTENT), 1);
    }

    function test_valueBearingLifecycleCallsRevertAtomically() public {
        uint256 activeId = registry.propose(KEY, address(candidate), CONTENT);
        uint256 pendingId = registry.propose(KEY, address(candidate), CONTENT);
        vm.prank(OWNER);
        registry.approve(activeId, 0, DECISION);
        bytes32 activeBefore = keccak256(abi.encode(registry.getProposal(activeId)));
        bytes32 pendingBefore = keccak256(abi.encode(registry.getProposal(pendingId)));
        bytes[4] memory calls = [
            abi.encodeCall(registry.propose, (KEY, address(candidate), CONTENT)),
            abi.encodeCall(registry.approve, (pendingId, activeId, DECISION)),
            abi.encodeCall(registry.reject, (pendingId, DECISION)),
            abi.encodeCall(registry.retire, (KEY, activeId, DECISION))
        ];
        vm.deal(OWNER, 4);
        for (uint256 i; i < calls.length; ++i) {
            vm.prank(OWNER);
            (bool ok,) = address(registry).call{value: 1}(calls[i]);
            assertFalse(ok, "nonpayable entry point accepted value");
        }
        assertEq(registry.proposalCount(), 2);
        assertEq(registry.activeProposal(KEY), activeId);
        assertEq(keccak256(abi.encode(registry.getProposal(activeId))), activeBefore);
        assertEq(keccak256(abi.encode(registry.getProposal(pendingId))), pendingBefore);
        assertEq(address(registry).balance, 0);
        assertEq(OWNER.balance, 4);
    }

    function _seedTwoKeys(MossExperimentRegistry target, bytes32 keyA, bytes32 keyB) private {
        target.propose(keyA, address(candidate), CONTENT);
        target.propose(keyB, address(candidate), CONTENT);
        target.propose(keyA, address(candidate), bytes32(uint256(1)));
        target.propose(keyB, address(candidate), bytes32(uint256(2)));
        vm.startPrank(OWNER);
        target.approve(1, 0, DECISION);
        target.approve(2, 0, DECISION);
        vm.stopPrank();
    }

    function _decideA(MossExperimentRegistry target, bytes32 key, bool retireAfter) private {
        target.approve(3, 1, DECISION);
        if (retireAfter) target.retire(key, 3, DECISION);
    }

    function _decideB(MossExperimentRegistry target, bool rejectInstead) private {
        if (rejectInstead) target.reject(4, DECISION);
        else target.approve(4, 2, DECISION);
    }

    function _nonzero(bytes32 value) private pure returns (bytes32) {
        return value == bytes32(0) ? bytes32(uint256(1)) : value;
    }
}
