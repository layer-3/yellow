// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.34;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @notice Yellow Network utility token. ERC20 with permit functionality.
 * Fixed 10 billion supply minted entirely to the treasury at deployment.
 */
contract YellowToken is ERC20Permit {
    uint256 public constant SUPPLY_CAP = 10_000_000_000 ether;

    error InvalidAddress();

    /**
     * @param treasury Address that receives the entire minted supply.
     */
    constructor(address treasury) ERC20Permit("Yellow") ERC20("Yellow", "YELLOW") {
        if (treasury == address(0)) revert InvalidAddress();
        _mint(treasury, SUPPLY_CAP);
    }
}
