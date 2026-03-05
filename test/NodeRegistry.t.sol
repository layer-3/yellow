// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {LockerTestBase} from "./Locker.t.sol";

import {ILock} from "../src/interfaces/ILock.sol";
import {NodeRegistry} from "../src/NodeRegistry.sol";
import {YellowToken} from "../src/Token.sol";

/// @dev Runs all shared ILock tests against NodeRegistry.
contract NodeRegistryTest_Locker is LockerTestBase {
    NodeRegistry nodeRegistry;

    function setUp() public override {
        token = new YellowToken(treasury);
        nodeRegistry = new NodeRegistry(address(token), UNLOCK_PERIOD);
        super.setUp();
    }

    function _vault() internal view override returns (ILock) {
        return ILock(address(nodeRegistry));
    }

    function _vaultAddress() internal view override returns (address) {
        return address(nodeRegistry);
    }
}

// -------------------------------------------------------------------------
// Constructor
// -------------------------------------------------------------------------
contract NodeRegistryTest_Constructor is Test {
    function test_revert_ifAssetIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(ILock.InvalidAddress.selector));
        new NodeRegistry(address(0), 14 days);
    }

    function test_revert_ifUnlockPeriodIsZero() public {
        YellowToken t = new YellowToken(address(this));
        vm.expectRevert(abi.encodeWithSelector(ILock.InvalidPeriod.selector));
        new NodeRegistry(address(t), 0);
    }

    function test_setsAssetAndPeriod() public {
        YellowToken t = new YellowToken(address(this));
        NodeRegistry v = new NodeRegistry(address(t), 14 days);
        assertEq(v.asset(), address(t));
        assertEq(v.ASSET(), address(t));
        assertEq(v.UNLOCK_PERIOD(), 14 days);
    }
}

contract NodeRegistryTest is Test {
    NodeRegistry nodeRegistry;
    YellowToken token;

    address treasury = address(2);
    address alice = address(3);
    address bob = address(4);
    address charlie = address(5);

    uint256 constant LOCK_AMOUNT = 1000 ether;

    function setUp() public {
        token = new YellowToken(treasury);
        nodeRegistry = new NodeRegistry(address(token), 14 days);

        vm.startPrank(treasury);
        require(token.transfer(alice, 10_000 ether));
        require(token.transfer(bob, 10_000 ether));
        vm.stopPrank();

        vm.prank(alice);
        token.approve(address(nodeRegistry), type(uint256).max);
        vm.prank(bob);
        token.approve(address(nodeRegistry), type(uint256).max);
    }

    // -------------------------------------------------------------------------
    // Delegation
    // -------------------------------------------------------------------------

    function test_delegate_selfDelegationActivatesVotes() public {
        vm.startPrank(alice);
        nodeRegistry.lock(alice, LOCK_AMOUNT);
        nodeRegistry.delegate(alice);
        vm.stopPrank();

        vm.roll(block.number + 1);
        assertEq(nodeRegistry.getVotes(alice), LOCK_AMOUNT);
    }

    function test_delegate_autoSelfDelegateOnFirstLock() public {
        vm.prank(alice);
        nodeRegistry.lock(alice, LOCK_AMOUNT);

        vm.roll(block.number + 1);
        // Auto-self-delegation means votes are immediately active
        assertEq(nodeRegistry.getVotes(alice), LOCK_AMOUNT);
        assertEq(nodeRegistry.delegates(alice), alice);
    }

    function test_delegate_toAnotherAddress() public {
        vm.startPrank(alice);
        nodeRegistry.lock(alice, LOCK_AMOUNT);
        nodeRegistry.delegate(bob);
        vm.stopPrank();

        vm.roll(block.number + 1);
        assertEq(nodeRegistry.getVotes(bob), LOCK_AMOUNT);
        assertEq(nodeRegistry.getVotes(alice), 0);
    }

    function test_delegate_changeDelegateMovesVotes() public {
        vm.startPrank(alice);
        nodeRegistry.lock(alice, LOCK_AMOUNT);
        nodeRegistry.delegate(bob);
        vm.stopPrank();

        vm.roll(block.number + 1);
        assertEq(nodeRegistry.getVotes(bob), LOCK_AMOUNT);

        vm.prank(alice);
        nodeRegistry.delegate(charlie);

        vm.roll(block.number + 1);
        assertEq(nodeRegistry.getVotes(bob), 0);
        assertEq(nodeRegistry.getVotes(charlie), LOCK_AMOUNT);
    }

    // -------------------------------------------------------------------------
    // Voting units on lock
    // -------------------------------------------------------------------------

    function test_lock_updatesVotingPower() public {
        vm.startPrank(alice);
        nodeRegistry.delegate(alice);
        nodeRegistry.lock(alice, LOCK_AMOUNT);
        vm.stopPrank();

        assertEq(nodeRegistry.getVotes(alice), LOCK_AMOUNT);
    }

    function test_lock_topUp_increasesVotingPower() public {
        vm.startPrank(alice);
        nodeRegistry.delegate(alice);
        nodeRegistry.lock(alice, LOCK_AMOUNT);
        nodeRegistry.lock(alice, LOCK_AMOUNT);
        vm.stopPrank();

        assertEq(nodeRegistry.getVotes(alice), LOCK_AMOUNT * 2);
    }

    // -------------------------------------------------------------------------
    // Voting power on unlock vs withdraw
    // -------------------------------------------------------------------------

    function test_unlock_removesVotingPower() public {
        vm.startPrank(alice);
        nodeRegistry.delegate(alice);
        nodeRegistry.lock(alice, LOCK_AMOUNT);
        nodeRegistry.unlock();
        vm.stopPrank();

        assertEq(nodeRegistry.getVotes(alice), 0);
    }

    function test_withdraw_removesVotingPower() public {
        vm.startPrank(alice);
        nodeRegistry.delegate(alice);
        nodeRegistry.lock(alice, LOCK_AMOUNT);
        nodeRegistry.unlock();
        vm.stopPrank();

        vm.warp(block.timestamp + 14 days);

        vm.prank(alice);
        nodeRegistry.withdraw(alice);

        assertEq(nodeRegistry.getVotes(alice), 0);
    }

    // -------------------------------------------------------------------------
    // Historical checkpoints
    // -------------------------------------------------------------------------

    function test_getVotes_reflectsLockAndWithdraw() public {
        // Before lock: no votes
        assertEq(nodeRegistry.getVotes(alice), 0);

        vm.startPrank(alice);
        nodeRegistry.delegate(alice);
        nodeRegistry.lock(alice, LOCK_AMOUNT);
        vm.stopPrank();

        // After lock: has votes
        assertEq(nodeRegistry.getVotes(alice), LOCK_AMOUNT);

        // After unlock: votes removed
        vm.prank(alice);
        nodeRegistry.unlock();
        assertEq(nodeRegistry.getVotes(alice), 0);

        // After relock: votes restored
        vm.prank(alice);
        nodeRegistry.relock();
        assertEq(nodeRegistry.getVotes(alice), LOCK_AMOUNT);
    }

    function test_getPastTotalSupply_tracksLockedTokens() public {
        vm.roll(10);

        vm.startPrank(alice);
        nodeRegistry.delegate(alice);
        nodeRegistry.lock(alice, LOCK_AMOUNT);
        vm.stopPrank();

        vm.roll(20);

        assertEq(nodeRegistry.getPastTotalSupply(10), LOCK_AMOUNT);

        // Bob locks
        vm.startPrank(bob);
        nodeRegistry.delegate(bob);
        nodeRegistry.lock(bob, LOCK_AMOUNT * 2);
        vm.stopPrank();

        vm.roll(30);

        assertEq(nodeRegistry.getPastTotalSupply(20), LOCK_AMOUNT * 3);
        // Historical snapshot unchanged
        assertEq(nodeRegistry.getPastTotalSupply(10), LOCK_AMOUNT);
    }

    // -------------------------------------------------------------------------
    // Multiple users
    // -------------------------------------------------------------------------

    function test_multipleUsers_independentVotingPower() public {
        vm.startPrank(alice);
        nodeRegistry.delegate(alice);
        nodeRegistry.lock(alice, LOCK_AMOUNT);
        vm.stopPrank();

        vm.startPrank(bob);
        nodeRegistry.delegate(bob);
        nodeRegistry.lock(bob, LOCK_AMOUNT * 2);
        vm.stopPrank();

        assertEq(nodeRegistry.getVotes(alice), LOCK_AMOUNT);
        assertEq(nodeRegistry.getVotes(bob), LOCK_AMOUNT * 2);
    }

    // -------------------------------------------------------------------------
    // Full lifecycle checkpoints
    // -------------------------------------------------------------------------

    function test_lockWithdrawRelock_checkpointsCorrect() public {
        vm.startPrank(alice);
        nodeRegistry.delegate(alice);

        nodeRegistry.lock(alice, LOCK_AMOUNT);
        assertEq(nodeRegistry.getVotes(alice), LOCK_AMOUNT);

        nodeRegistry.unlock();
        assertEq(nodeRegistry.getVotes(alice), 0);

        vm.warp(block.timestamp + 14 days);
        nodeRegistry.withdraw(alice);
        assertEq(nodeRegistry.getVotes(alice), 0);

        nodeRegistry.lock(alice, LOCK_AMOUNT * 2);
        assertEq(nodeRegistry.getVotes(alice), LOCK_AMOUNT * 2);

        vm.stopPrank();
    }
}
