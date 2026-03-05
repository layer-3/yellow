// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Faucet — YELLOW testnet token faucet
/// @notice Dispenses a fixed amount of YELLOW per call with a per-address cooldown.
contract Faucet {
    IERC20 public immutable TOKEN;
    address public owner;
    uint256 public dripAmount;
    uint256 public cooldown;

    mapping(address => uint256) public lastDrip;

    event Dripped(address indexed recipient, uint256 amount);
    event DripAmountUpdated(uint256 newAmount);
    event CooldownUpdated(uint256 newCooldown);
    event OwnerUpdated(address indexed newOwner);

    modifier onlyOwner() {
        _onlyOwner();
        _;
    }

    function _onlyOwner() internal view {
        require(msg.sender == owner, "Faucet: not owner");
    }

    /// @param _token      YELLOW token address
    /// @param _dripAmount Amount dispensed per drip (in wei)
    /// @param _cooldown   Seconds between drips per address
    constructor(IERC20 _token, uint256 _dripAmount, uint256 _cooldown) {
        TOKEN = _token;
        owner = msg.sender;
        dripAmount = _dripAmount;
        cooldown = _cooldown;
    }

    /// @notice Drip YELLOW to msg.sender.
    function drip() external {
        _dripTo(msg.sender);
    }

    /// @notice Drip YELLOW to a specified address (for batch use).
    function dripTo(address recipient) external {
        _dripTo(recipient);
    }

    function _dripTo(address recipient) internal {
        require(
            lastDrip[recipient] == 0 || block.timestamp >= lastDrip[recipient] + cooldown, "Faucet: cooldown active"
        );
        require(TOKEN.balanceOf(address(this)) >= dripAmount, "Faucet: insufficient balance");

        lastDrip[recipient] = block.timestamp;
        require(TOKEN.transfer(recipient, dripAmount), "Faucet: transfer failed");

        emit Dripped(recipient, dripAmount);
    }

    /// @notice Owner can update the drip amount.
    function setDripAmount(uint256 _dripAmount) external onlyOwner {
        dripAmount = _dripAmount;
        emit DripAmountUpdated(_dripAmount);
    }

    /// @notice Owner can update the cooldown period.
    function setCooldown(uint256 _cooldown) external onlyOwner {
        cooldown = _cooldown;
        emit CooldownUpdated(_cooldown);
    }

    /// @notice Owner can transfer ownership.
    function setOwner(address _owner) external onlyOwner {
        require(_owner != address(0), "Faucet: zero address");
        owner = _owner;
        emit OwnerUpdated(_owner);
    }

    /// @notice Owner can withdraw remaining tokens.
    function withdraw(uint256 amount) external onlyOwner {
        require(TOKEN.transfer(owner, amount), "Faucet: withdraw failed");
    }
}
