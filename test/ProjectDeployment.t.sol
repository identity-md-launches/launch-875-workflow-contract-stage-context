// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {LaunchToken} from "../src/LaunchToken.sol";
import {MossExperimentRegistry} from "../src/MossExperimentRegistry.sol";

contract LocalProjectFactory {
    function deploy(address owner) external returns (LaunchToken token, MossExperimentRegistry registry) {
        token = new LaunchToken{salt: bytes32(uint256(1))}();
        registry = new MossExperimentRegistry{salt: bytes32(uint256(2))}(address(token), owner);
    }
}

contract ProjectDeploymentTest is Test {
    function test_factoryDeploymentIsFullyConfiguredAndKeepsSupply() public {
        address owner = address(0xA11CE);
        LocalProjectFactory factory = new LocalProjectFactory();
        bytes32 tokenInitHash = keccak256(type(LaunchToken).creationCode);
        address predictedToken = address(
            uint160(
                uint256(keccak256(abi.encodePacked(bytes1(0xff), address(factory), bytes32(uint256(1)), tokenInitHash)))
            )
        );
        bytes32 registryInitHash =
            keccak256(abi.encodePacked(type(MossExperimentRegistry).creationCode, abi.encode(predictedToken, owner)));
        address predictedRegistry = address(
            uint160(
                uint256(
                    keccak256(abi.encodePacked(bytes1(0xff), address(factory), bytes32(uint256(2)), registryInitHash))
                )
            )
        );

        (LaunchToken token, MossExperimentRegistry registry) = factory.deploy(owner);
        assertEq(address(token), predictedToken);
        assertEq(address(registry), predictedRegistry);
        assertEq(token.balanceOf(address(factory)), 1e27);
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.balanceOf(owner), 0);
        assertEq(token.balanceOf(address(registry)), 0);
        assertEq(registry.owner(), owner);
        assertEq(registry.token(), address(token));
        vm.expectRevert(MossExperimentRegistry.Unauthorized.selector);
        vm.prank(address(factory));
        registry.approve(1, 0, keccak256("decision"));

        _checkRuntime(address(token));
        _checkRuntime(address(registry));
    }

    function test_factoryCannotAccidentallyBeConfiguredAsOwner() public {
        LocalProjectFactory factory = new LocalProjectFactory();
        vm.expectRevert(MossExperimentRegistry.InvalidOwner.selector);
        factory.deploy(address(factory));
    }

    function test_bothConstructorsAreNonpayable() public {
        vm.deal(address(this), 2 ether);
        vm.expectRevert();
        _createWithValue(type(LaunchToken).creationCode);
        LaunchToken token = new LaunchToken();
        vm.expectRevert();
        _createWithValue(
            abi.encodePacked(type(MossExperimentRegistry).creationCode, abi.encode(address(token), address(0xA11CE)))
        );
    }

    function _createWithValue(bytes memory code) internal {
        address deployed;
        assembly ("memory-safe") {
            deployed := create(1, add(code, 32), mload(code))
        }
        require(deployed != address(0), "nonpayable constructor");
    }

    function _checkRuntime(address deployed) internal view {
        bytes memory code = deployed.code;
        assertGt(code.length, 0);
        assertLe(code.length, 24_576);
        for (uint256 i; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden opcode");
        }
    }
}
