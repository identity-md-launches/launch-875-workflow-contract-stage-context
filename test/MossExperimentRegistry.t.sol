// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {LaunchToken} from "../src/LaunchToken.sol";
import {MossExperimentRegistry} from "../src/MossExperimentRegistry.sol";

// A deliberately uncallable candidate demonstrates that listing never executes code.
contract UncallableExperiment {
    fallback() external {
        revert("must never be called");
    }
}

contract MossExperimentRegistryTest is Test {
    LaunchToken internal token;
    MossExperimentRegistry internal registry;
    UncallableExperiment internal first;
    UncallableExperiment internal second;
    address internal constant OWNER = address(0xA11CE);
    address internal constant RESEARCHER = address(0xB0B);
    bytes32 internal constant KEY = keccak256("moss.example");
    bytes32 internal constant CONTENT = keccak256("experiment document");
    bytes32 internal constant DECISION = keccak256("review document");

    event ExperimentProposed(
        uint256 indexed proposalId,
        bytes32 indexed key,
        address indexed proposer,
        address implementation,
        bytes32 codeHash,
        bytes32 contentHash
    );
    event ExperimentApproved(
        uint256 indexed proposalId, bytes32 indexed key, uint256 previousProposalId, bytes32 decisionHash
    );
    event ExperimentRetired(uint256 indexed proposalId, bytes32 indexed key, bytes32 decisionHash);
    event ExperimentRejected(uint256 indexed proposalId, bytes32 indexed key, bytes32 decisionHash);

    function setUp() public {
        token = new LaunchToken();
        registry = new MossExperimentRegistry(address(token), OWNER);
        first = new UncallableExperiment();
        second = new UncallableExperiment();
    }

    function test_constructorUsesExplicitOwnerAndPreservesSupply() public view {
        assertEq(registry.owner(), OWNER);
        assertEq(registry.token(), address(token));
        assertEq(registry.proposalCount(), 0);
        assertEq(token.balanceOf(address(this)), 1e27);
        assertEq(token.balanceOf(address(registry)), 0);
    }

    function test_constructorRejectsMissingTokenCode() public {
        vm.expectRevert(MossExperimentRegistry.InvalidToken.selector);
        new MossExperimentRegistry(address(0), OWNER);
        vm.expectRevert(MossExperimentRegistry.InvalidToken.selector);
        new MossExperimentRegistry(RESEARCHER, OWNER);
    }

    function test_constructorRejectsInvalidOwnerIncludingFactory() public {
        vm.expectRevert(MossExperimentRegistry.InvalidOwner.selector);
        new MossExperimentRegistry(address(token), address(0));
        vm.expectRevert(MossExperimentRegistry.InvalidOwner.selector);
        new MossExperimentRegistry(address(token), address(this));
        vm.expectRevert(MossExperimentRegistry.InvalidOwner.selector);
        new MossExperimentRegistry(address(token), address(token));
    }

    function test_proposalRecordsResearcherAndImmutableContents() public {
        vm.expectEmit(true, true, true, true, address(registry));
        emit ExperimentProposed(1, KEY, RESEARCHER, address(first), address(first).codehash, CONTENT);
        uint256 id = _propose(KEY, address(first));
        MossExperimentRegistry.Proposal memory p = registry.getProposal(id);
        assertEq(id, 1);
        assertEq(registry.proposalCount(), 1);
        assertEq(p.key, KEY);
        assertEq(p.implementation, address(first));
        assertEq(p.codeHash, address(first).codehash);
        assertEq(p.contentHash, CONTENT);
        assertEq(p.proposer, RESEARCHER);
        assertEq(uint8(p.status), uint8(MossExperimentRegistry.Status.Pending));
        assertEq(registry.activeProposal(KEY), 0);
        assertFalse(registry.isActive(id));
    }

    function test_approvalEmitsDecisionAndActivatesWithoutCallingCandidate() public {
        uint256 id = _propose(KEY, address(first));
        vm.expectEmit(true, true, false, true, address(registry));
        emit ExperimentApproved(id, KEY, 0, DECISION);
        _approve(id, 0);
        assertTrue(registry.isActive(id));
        assertEq(registry.activeProposal(KEY), id);
        assertEq(token.balanceOf(address(this)), 1e27);
    }

    function test_replacementPreservesOldProposalAndRetiresIt() public {
        uint256 oldId = _propose(KEY, address(first));
        _approve(oldId, 0);
        uint256 newId = _propose(KEY, address(second));
        vm.expectEmit(true, true, false, true, address(registry));
        emit ExperimentRetired(oldId, KEY, DECISION);
        vm.expectEmit(true, true, false, true, address(registry));
        emit ExperimentApproved(newId, KEY, oldId, DECISION);
        _approve(newId, oldId);
        assertFalse(registry.isActive(oldId));
        assertTrue(registry.isActive(newId));
        MossExperimentRegistry.Proposal memory old = registry.getProposal(oldId);
        assertEq(uint8(old.status), uint8(MossExperimentRegistry.Status.Retired));
        assertEq(old.implementation, address(first));
        assertEq(old.contentHash, CONTENT);
        assertEq(old.proposer, RESEARCHER);
        assertEq(registry.token(), address(token));
    }

    function test_independentKeysCoexist() public {
        uint256 a = _propose(KEY, address(first));
        uint256 b = _propose(bytes32(uint256(2)), address(second));
        _approve(a, 0);
        _approve(b, 0);
        assertTrue(registry.isActive(a));
        assertTrue(registry.isActive(b));
        vm.prank(OWNER);
        registry.retire(KEY, a, DECISION);
        assertTrue(registry.isActive(b));
    }

    function test_retireThenApproveNewVersion() public {
        uint256 id = _propose(KEY, address(first));
        _approve(id, 0);
        vm.expectEmit(true, true, false, true, address(registry));
        emit ExperimentRetired(id, KEY, DECISION);
        vm.prank(OWNER);
        registry.retire(KEY, id, DECISION);
        assertFalse(registry.isActive(id));
        assertEq(registry.activeProposal(KEY), 0);
        uint256 next = _propose(KEY, address(second));
        _approve(next, 0);
        assertTrue(registry.isActive(next));
    }

    function test_rejectionPreservesActiveVersionAndRejectedHistory() public {
        uint256 active = _propose(KEY, address(first));
        _approve(active, 0);
        uint256 rejected = _propose(KEY, address(second));
        vm.expectEmit(true, true, false, true, address(registry));
        emit ExperimentRejected(rejected, KEY, DECISION);
        vm.prank(OWNER);
        registry.reject(rejected, DECISION);
        assertEq(uint8(registry.getProposal(rejected).status), uint8(MossExperimentRegistry.Status.Rejected));
        assertEq(registry.getProposal(rejected).implementation, address(second));
        assertTrue(registry.isActive(active));
        assertFalse(registry.isActive(rejected));
    }

    function testFuzz_nonOwnerCannotDecide(address caller) public {
        vm.assume(caller != OWNER);
        uint256 id = _propose(KEY, address(first));
        vm.expectRevert(MossExperimentRegistry.Unauthorized.selector);
        vm.prank(caller);
        registry.approve(id, 0, DECISION);
        vm.expectRevert(MossExperimentRegistry.Unauthorized.selector);
        vm.prank(caller);
        registry.reject(id, DECISION);
        _approve(id, 0);
        vm.expectRevert(MossExperimentRegistry.Unauthorized.selector);
        vm.prank(caller);
        registry.retire(KEY, id, DECISION);
        assertTrue(registry.isActive(id));
    }

    function test_staleApprovalCannotReplaceUnreviewedVersion() public {
        uint256 a = _propose(KEY, address(first));
        uint256 b = _propose(KEY, address(second));
        _approve(a, 0);
        vm.expectRevert(abi.encodeWithSelector(MossExperimentRegistry.StaleActiveProposal.selector, 0, a));
        _approve(b, 0);
        assertTrue(registry.isActive(a));
        assertEq(uint8(registry.getProposal(b).status), uint8(MossExperimentRegistry.Status.Pending));
    }

    function test_staleRetirementCannotRetireReplacement() public {
        uint256 a = _propose(KEY, address(first));
        uint256 b = _propose(KEY, address(second));
        _approve(a, 0);
        _approve(b, a);
        vm.expectRevert(abi.encodeWithSelector(MossExperimentRegistry.StaleActiveProposal.selector, a, b));
        vm.prank(OWNER);
        registry.retire(KEY, a, DECISION);
        assertTrue(registry.isActive(b));
    }

    function test_changedCodeCannotBeApprovedAndOldActiveSurvives() public {
        uint256 a = _propose(KEY, address(first));
        _approve(a, 0);
        uint256 b = _propose(KEY, address(second));
        vm.etch(address(second), hex"60006000fd");
        vm.expectRevert(abi.encodeWithSelector(MossExperimentRegistry.ImplementationChanged.selector, b));
        _approve(b, a);
        assertTrue(registry.isActive(a));
        assertEq(uint8(registry.getProposal(b).status), uint8(MossExperimentRegistry.Status.Pending));
    }

    function test_missingCodeCannotBeApproved() public {
        uint256 id = _propose(KEY, address(first));
        vm.etch(address(first), hex"");
        vm.expectRevert(abi.encodeWithSelector(MossExperimentRegistry.ImplementationChanged.selector, id));
        _approve(id, 0);
    }

    function test_changedActiveCodeIsFlaggedAndCanStillBeRetired() public {
        uint256 id = _propose(KEY, address(first));
        _approve(id, 0);
        vm.etch(address(first), hex"60006000fd");
        assertFalse(registry.isActive(id));
        assertEq(registry.activeProposal(KEY), id);
        vm.prank(OWNER);
        registry.retire(KEY, id, DECISION);
        assertEq(registry.activeProposal(KEY), 0);
    }

    function test_invalidProposalInputsRevertWithoutConsumingIds() public {
        vm.expectRevert(MossExperimentRegistry.EmptyHash.selector);
        registry.propose(bytes32(0), address(first), CONTENT);
        vm.expectRevert(MossExperimentRegistry.EmptyHash.selector);
        registry.propose(KEY, address(first), bytes32(0));
        address[4] memory invalid = [address(0), RESEARCHER, address(token), address(registry)];
        for (uint256 i; i < invalid.length; ++i) {
            vm.expectRevert(MossExperimentRegistry.InvalidImplementation.selector);
            registry.propose(KEY, invalid[i], CONTENT);
        }
        assertEq(registry.proposalCount(), 0);
    }

    function test_emptyDecisionRejectedForEveryTransition() public {
        uint256 id = _propose(KEY, address(first));
        vm.startPrank(OWNER);
        vm.expectRevert(MossExperimentRegistry.EmptyHash.selector);
        registry.approve(id, 0, bytes32(0));
        vm.expectRevert(MossExperimentRegistry.EmptyHash.selector);
        registry.reject(id, bytes32(0));
        registry.approve(id, 0, DECISION);
        vm.expectRevert(MossExperimentRegistry.EmptyHash.selector);
        registry.retire(KEY, id, bytes32(0));
        vm.stopPrank();
        assertTrue(registry.isActive(id));
    }

    function test_unknownIdsAndEmptyRetirementRevert() public {
        vm.expectRevert(abi.encodeWithSelector(MossExperimentRegistry.UnknownProposal.selector, 0));
        registry.getProposal(0);
        vm.expectRevert(abi.encodeWithSelector(MossExperimentRegistry.UnknownProposal.selector, 1));
        _approve(1, 0);
        vm.startPrank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(MossExperimentRegistry.UnknownProposal.selector, 1));
        registry.reject(1, DECISION);
        vm.expectRevert(abi.encodeWithSelector(MossExperimentRegistry.NoActiveProposal.selector, KEY));
        registry.retire(KEY, 0, DECISION);
        vm.stopPrank();
        assertFalse(registry.isActive(0));
        assertFalse(registry.isActive(type(uint256).max));
    }

    function test_duplicateApprovalAndRejectionOfActiveVersionRevert() public {
        uint256 id = _propose(KEY, address(first));
        _approve(id, 0);
        _expectInvalidStatus(id, MossExperimentRegistry.Status.Active);
        _approve(id, id);
        _expectInvalidStatus(id, MossExperimentRegistry.Status.Active);
        vm.prank(OWNER);
        registry.reject(id, DECISION);
        assertTrue(registry.isActive(id));
    }

    function test_retiredAndRejectedProposalsCannotBeReactivatedOrRejectedAgain() public {
        uint256 a = _propose(KEY, address(first));
        uint256 b = _propose(KEY, address(second));
        _approve(a, 0);
        vm.startPrank(OWNER);
        registry.retire(KEY, a, DECISION);
        registry.reject(b, DECISION);
        vm.stopPrank();
        for (uint256 id = a; id <= b; ++id) {
            MossExperimentRegistry.Status status = registry.getProposal(id).status;
            _expectInvalidStatus(id, status);
            _approve(id, 0);
            _expectInvalidStatus(id, status);
            vm.prank(OWNER);
            registry.reject(id, DECISION);
        }
        vm.expectRevert(abi.encodeWithSelector(MossExperimentRegistry.NoActiveProposal.selector, KEY));
        vm.prank(OWNER);
        registry.retire(KEY, a, DECISION);
    }

    function test_proposalSpamCannotReserveKeysOrModifyActiveVersion() public {
        uint256 a = _propose(KEY, address(first));
        _approve(a, 0);
        for (uint256 i; i < 10; ++i) {
            _propose(KEY, address(second));
        }
        assertTrue(registry.isActive(a));
        assertEq(registry.activeProposal(KEY), a);
        assertEq(registry.proposalCount(), 11);
    }

    function test_rejectsEtherAndUnknownExecutionSelectors() public {
        vm.deal(address(this), 1 ether);
        (bool acceptsEther,) = address(registry).call{value: 1}("");
        assertFalse(acceptsEther);
        vm.prank(OWNER);
        (bool canExecute,) =
            address(registry).call(abi.encodeWithSignature("execute(address,bytes)", address(first), hex""));
        assertFalse(canExecute);
        assertEq(address(registry).balance, 0);
    }

    function _propose(bytes32 key, address implementation) internal returns (uint256) {
        vm.prank(RESEARCHER);
        return registry.propose(key, implementation, CONTENT);
    }

    function _approve(uint256 id, uint256 expectedActive) internal {
        vm.prank(OWNER);
        registry.approve(id, expectedActive, DECISION);
    }

    function _expectInvalidStatus(uint256 id, MossExperimentRegistry.Status status) internal {
        vm.expectRevert(abi.encodeWithSelector(MossExperimentRegistry.InvalidStatus.selector, id, status));
    }
}
