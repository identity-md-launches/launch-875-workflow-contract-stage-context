// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {LaunchToken} from "../src/LaunchToken.sol";
import {MossExperimentRegistry} from "../src/MossExperimentRegistry.sol";

contract StatefulCandidate {
    function version() external pure returns (uint256) {
        return 1;
    }
}

contract MossHandler is Test {
    LaunchToken public immutable token;
    MossExperimentRegistry public immutable registry;
    address public immutable candidate;
    address[3] public actors = [address(0xA11CE), address(0xB0B), address(0xCAFE)];
    mapping(uint256 id => bytes32 digest) public proposedContents;
    mapping(uint256 id => bool wasFinalized) public finalized;

    constructor(LaunchToken token_, MossExperimentRegistry registry_, address candidate_) {
        token = token_;
        registry = registry_;
        candidate = candidate_;
    }

    function transfer(uint8 senderSeed, uint8 receiverSeed, uint256 value) external {
        address sender = actors[senderSeed % 3];
        address receiver = actors[receiverSeed % 3];
        value = bound(value, 0, token.balanceOf(sender));
        vm.prank(sender);
        token.transfer(receiver, value);
    }

    function approveAndSpend(uint8 ownerSeed, uint8 spenderSeed, uint8 receiverSeed, uint256 value) external {
        address from = actors[ownerSeed % 3];
        address spender = actors[spenderSeed % 3];
        value = bound(value, 0, token.balanceOf(from));
        vm.prank(from);
        token.approve(spender, value);
        vm.prank(spender);
        token.transferFrom(from, actors[receiverSeed % 3], value);
        assertEq(token.allowance(from, spender), 0);
    }

    function propose(uint8 keySeed, bytes32 contentSeed) external {
        bytes32 content = keccak256(abi.encode(contentSeed, registry.proposalCount()));
        if (content == bytes32(0)) return;
        uint256 id = registry.propose(bytes32(uint256(keySeed % 4) + 1), candidate, content);
        proposedContents[id] = _digest(registry.getProposal(id));
    }

    function approve(uint256 seed) external {
        if (registry.proposalCount() == 0) return;
        uint256 id = bound(seed, 1, registry.proposalCount());
        MossExperimentRegistry.Proposal memory p = registry.getProposal(id);
        if (p.status != MossExperimentRegistry.Status.Pending) return;
        uint256 previous = registry.activeProposal(p.key);
        vm.prank(registry.owner());
        registry.approve(id, previous, keccak256("approval"));
        if (previous != 0) finalized[previous] = true;
    }

    function reject(uint256 seed) external {
        if (registry.proposalCount() == 0) return;
        uint256 id = bound(seed, 1, registry.proposalCount());
        if (registry.getProposal(id).status != MossExperimentRegistry.Status.Pending) return;
        vm.prank(registry.owner());
        registry.reject(id, keccak256("rejection"));
        finalized[id] = true;
    }

    function retire(uint8 keySeed) external {
        bytes32 key = bytes32(uint256(keySeed % 4) + 1);
        uint256 id = registry.activeProposal(key);
        if (id == 0) return;
        vm.prank(registry.owner());
        registry.retire(key, id, keccak256("retirement"));
        finalized[id] = true;
    }

    function _digest(MossExperimentRegistry.Proposal memory p) internal pure returns (bytes32) {
        return keccak256(abi.encode(p.key, p.implementation, p.codeHash, p.contentHash, p.proposer));
    }
}

contract MossStatefulTest is Test {
    LaunchToken internal token;
    MossExperimentRegistry internal registry;
    MossHandler internal handler;

    function setUp() public {
        token = new LaunchToken();
        registry = new MossExperimentRegistry(address(token), address(0x1234));
        handler = new MossHandler(token, registry, address(new StatefulCandidate()));
        token.transfer(handler.actors(0), 1e27);

        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = MossHandler.transfer.selector;
        selectors[1] = MossHandler.approveAndSpend.selector;
        selectors[2] = MossHandler.propose.selector;
        selectors[3] = MossHandler.approve.selector;
        selectors[4] = MossHandler.reject.selector;
        selectors[5] = MossHandler.retire.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_supplyAndBalancesAreConserved() public view {
        assertEq(token.totalSupply(), 1e27);
        uint256 total;
        for (uint256 i; i < 3; ++i) {
            total += token.balanceOf(handler.actors(i));
        }
        assertEq(total, 1e27);
        assertEq(token.balanceOf(address(registry)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    function invariant_historyAndActiveVersionsRemainConsistent() public view {
        for (uint256 id = 1; id <= registry.proposalCount(); ++id) {
            MossExperimentRegistry.Proposal memory p = registry.getProposal(id);
            assertEq(
                keccak256(abi.encode(p.key, p.implementation, p.codeHash, p.contentHash, p.proposer)),
                handler.proposedContents(id)
            );
            if (p.status == MossExperimentRegistry.Status.Active) {
                assertEq(registry.activeProposal(p.key), id);
                assertTrue(registry.isActive(id));
            } else {
                assertFalse(registry.isActive(id));
                assertNotEq(registry.activeProposal(p.key), id);
            }
            if (handler.finalized(id)) {
                assertTrue(
                    p.status == MossExperimentRegistry.Status.Retired
                        || p.status == MossExperimentRegistry.Status.Rejected
                );
            }
        }
        for (uint256 key = 1; key <= 4; ++key) {
            uint256 active = registry.activeProposal(bytes32(key));
            if (active != 0) {
                assertEq(registry.getProposal(active).key, bytes32(key));
                assertTrue(registry.isActive(active));
            }
        }
        assertEq(registry.token(), address(token));
        assertEq(registry.owner(), address(0x1234));
    }
}
