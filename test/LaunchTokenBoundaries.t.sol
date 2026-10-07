// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {LaunchToken} from "src/LaunchToken.sol";

/// forge-config: default.fuzz.runs = 1000
contract LaunchTokenBoundariesTest is Test {
    LaunchToken private token;
    address private constant ALICE = address(0xA11CE);
    address private constant SPENDER = address(0xB0B);
    uint256 private constant SUPPLY = 1e27;

    function setUp() public {
        token = new LaunchToken();
    }

    function testFuzz_delegatedSelfTransferConservesBalanceButSpendsAllowance(uint256 approval, uint256 amount) public {
        uint256 limit = approval < SUPPLY ? approval : SUPPLY;
        _selfTransfer(approval, bound(amount, 0, limit));
    }

    function test_delegatedSelfTransferAtZeroOneFullSupplyAndAllowanceLimits() public {
        _selfTransfer(0, 0);
        _selfTransfer(1, 1);
        _selfTransfer(SUPPLY, SUPPLY);
        _selfTransfer(type(uint256).max - 1, SUPPLY);
        _selfTransfer(type(uint256).max, SUPPLY);
    }

    function test_fullSupplyRoundTripAndOneWeiOverspend() public {
        assertTrue(token.transfer(ALICE, SUPPLY));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, type(uint256).max - 1));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, address(this), SUPPLY));
        uint256 remaining = type(uint256).max - 1 - SUPPLY;
        assertEq(token.allowance(ALICE, SPENDER), remaining);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, address(this), 1);
        assertEq(token.allowance(ALICE, SPENDER), remaining);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maxAmountCannotWrapBalancesOrConsumeInfiniteAllowance() public {
        token.approve(SPENDER, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function _selfTransfer(uint256 approval, uint256 amount) private {
        token.approve(SPENDER, approval);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.allowance(address(this), SPENDER), approval == type(uint256).max ? approval : approval - amount);
    }
}
