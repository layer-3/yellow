// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title Treasury
 * @notice Secure vault for DAO assets.
 */
contract Treasury is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Human-readable label for this treasury (e.g. "Grants", "Operations").
    string public name;

    event Withdrawn(address indexed token, address indexed to, uint256 amount);

    constructor(address initialOwner, string memory name_) Ownable(initialOwner) {
        name = name_;
    }

    /**
     * @notice Moves funds out of the treasury.
     * @param token Use address(0) for ETH, otherwise ERC20 address.
     * @param to Destination address.
     * @param amount Amount to transfer (for ERC20 fee-on-transfer tokens,
     *        the event emits the actual amount received by `to`).
     */
    function withdraw(address token, address to, uint256 amount) external onlyOwner nonReentrant {
        require(to != address(0), "Zero address target");
        require(amount > 0, "Zero amount");

        if (token == address(0)) {
            require(address(this).balance >= amount, "Insufficient ETH");
            (bool success,) = payable(to).call{value: amount}("");
            require(success, "ETH transfer failed");
            emit Withdrawn(token, to, amount);
        } else {
            uint256 balBefore = IERC20(token).balanceOf(to);
            IERC20(token).safeTransfer(to, amount);
            uint256 received = IERC20(token).balanceOf(to) - balBefore;
            emit Withdrawn(token, to, received);
        }
    }

    receive() external payable {}
}
