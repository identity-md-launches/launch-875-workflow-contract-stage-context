// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {LaunchToken} from "src/LaunchToken.sol";

/// @dev Expected balances and allowances come from submitted operations, never token getters.
/// Approval and spending are separate actions so revocations, partial spends, self-transfers,
/// and competing spenders can interleave over an entire invariant sequence.
contract LaunchTokenModelHandler is Test {
    LaunchToken public immutable token;
    address[4] public actors = [address(0xA101), address(0xA102), address(0xA103), address(0xA104)];
    mapping(address => uint256) public balance;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(LaunchToken token_) {
        token = token_;
        for (uint256 i; i < actors.length; ++i) {
            balance[actors[i]] = 1e27 / actors.length;
        }
    }

    function approve(uint8 fromSeed, uint8 spenderSeed, uint256 amount, uint8 mode) external {
        address from = actors[fromSeed % 4];
        address spender = actors[spenderSeed % 4];
        mode %= 5;
        if (mode == 0) amount = 0;
        else if (mode == 1) amount = type(uint256).max;
        else if (mode == 2) amount = type(uint256).max - 1;
        else if (mode == 3) amount = bound(amount, 0, 1e27);
        vm.prank(from);
        assertTrue(token.approve(spender, amount));
        allowance[from][spender] = amount;
    }

    function transfer(uint8 fromSeed, uint8 toSeed, uint256 amount) external {
        address from = actors[fromSeed % 4];
        address to = actors[toSeed % 4];
        amount = bound(amount, 0, balance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _move(from, to, amount);
    }

    function spend(uint8 fromSeed, uint8 spenderSeed, uint8 toSeed, uint256 amount) external {
        address from = actors[fromSeed % 4];
        address spender = actors[spenderSeed % 4];
        uint256 available = balance[from];
        if (allowance[from][spender] < available) available = allowance[from][spender];
        _spend(from, spender, actors[toSeed % 4], bound(amount, 0, available));
    }

    /// @dev Deliberately reaches insufficient allowance/balance with no catch-all revert handling.
    function attemptSpend(uint8 fromSeed, uint8 spenderSeed, uint8 toSeed, uint256 amount, bool small) external {
        address from = actors[fromSeed % 4];
        address spender = actors[spenderSeed % 4];
        if (small) amount = bound(amount, 0, 1e27 + 1);
        _spend(from, spender, actors[toSeed % 4], amount);
    }

    function invalidTransfer(uint8 fromSeed, uint8 toSeed, uint256 amount, bool zeroRecipient) external {
        address from = actors[fromSeed % 4];
        address to = zeroRecipient ? address(0) : actors[toSeed % 4];
        if (zeroRecipient) {
            amount = bound(amount, 0, balance[from]);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        } else {
            amount = bound(amount, balance[from] + 1, type(uint256).max);
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance[from], amount)
            );
        }
        vm.prank(from);
        token.transfer(to, amount);
        // No model update: the invariant must observe complete rollback, including allowances.
    }

    function _spend(address from, address spender, address to, uint256 amount) private {
        uint256 approved = allowance[from][spender];
        if (amount > approved) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
            );
        } else if (amount > balance[from]) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance[from], amount)
            );
        } else {
            vm.prank(spender);
            assertTrue(token.transferFrom(from, to, amount));
            if (approved != type(uint256).max) allowance[from][spender] -= amount;
            _move(from, to, amount);
            return;
        }
        vm.prank(spender);
        token.transferFrom(from, to, amount);
    }

    function _move(address from, address to, uint256 amount) private {
        balance[from] -= amount;
        balance[to] += amount;
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 96
/// forge-config: default.invariant.fail-on-revert = true
contract LaunchTokenModelTest is Test {
    LaunchToken private token;
    LaunchTokenModelHandler private handler;

    function setUp() public {
        token = new LaunchToken();
        handler = new LaunchTokenModelHandler(token);
        for (uint256 i; i < 4; ++i) {
            token.transfer(handler.actors(i), 1e27 / 4);
        }

        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = handler.approve.selector;
        selectors[1] = handler.transfer.selector;
        selectors[2] = handler.spend.selector;
        selectors[3] = handler.attemptSpend.selector;
        selectors[4] = handler.invalidTransfer.selector;
        targetSelector(FuzzSelector(address(handler), selectors));
        targetContract(address(handler));
    }

    function invariant_exactBalancesAndIndependentAllowances() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 actual = token.balanceOf(actor);
            assertEq(actual, handler.balance(actor), "unexpected balance movement");
            sum += actual;
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(actor, spender), handler.allowance(actor, spender), "allowance mismatch");
            }
        }
        assertEq(sum, 1e27);
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(this)), 0);
    }

    /// @dev Guarantees the model exercises nonzero spending and every failure branch, regardless of seed.
    function test_modelExercisesRevocationRollbackAndAllowanceBoundaries() public {
        handler.approve(0, 1, 0, 1); // Infinite approval.
        handler.spend(0, 1, 0, 1); // Delegated self-transfer spends no infinite allowance.
        handler.spend(0, 1, 2, 1);
        handler.approve(0, 1, 0, 2); // Largest finite approval must decrement.
        handler.spend(0, 1, 2, 1);
        handler.approve(0, 1, 0, 0); // Revoke after partial spending.
        handler.attemptSpend(0, 1, 2, 1, false);
        handler.approve(0, 1, 0, 1);
        handler.attemptSpend(0, 1, 2, type(uint256).max, false); // Balance failure, approval survives.
        handler.invalidTransfer(0, 2, 0, true);
        handler.invalidTransfer(0, 2, type(uint256).max, false);
        handler.transfer(0, 3, type(uint256).max);
        invariant_exactBalancesAndIndependentAllowances();
    }
}
