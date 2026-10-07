// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Moss's immutable, plain ERC-20 launch token.
/// @dev The launch factory receives the entire supply and performs the policy distribution.
contract LaunchToken is ERC20 {
    constructor() ERC20("Moss", "Moss") {
        _mint(msg.sender, 1_000_000_000 * 10 ** 18);
    }
}
