// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {NodeRegistry} from "../src/NodeRegistry.sol";
import {YellowToken} from "../src/Token.sol";

contract LockerVotesTest is Test {
    NodeRegistry locker;
    YellowToken token;

    address treasury = address(2);
    address alice = address(3);
    address bob = address(4);
    address charlie = address(5);

    uint256 constant LOCK_AMOUNT = 1000 ether;

    function setUp() public {
        token = new YellowToken(treasury);
        locker = new NodeRegistry(address(token), 14 days);

        vm.startPrank(treasury);
        require(token.transfer(alice, 10_000 ether));
        require(token.transfer(bob, 10_000 ether));
        vm.stopPrank();

        vm.prank(alice);
        token.approve(address(locker), type(uint256).max);
        vm.prank(bob);
        token.approve(address(locker), type(uint256).max);
    }

    // -------------------------------------------------------------------------
    // Delegation
    // -------------------------------------------------------------------------

    function test_delegate_selfDelegationActivatesVotes() public {
        vm.startPrank(alice);
        locker.lock(alice, LOCK_AMOUNT);
        locker.delegate(alice);
        vm.stopPrank();

        vm.roll(block.number + 1);
        assertEq(locker.getVotes(alice), LOCK_AMOUNT);
    }

    function test_delegate_autoSelfDelegateOnFirstLock() public {
        vm.prank(alice);
        locker.lock(alice, LOCK_AMOUNT);

        vm.roll(block.number + 1);
        // Auto-self-delegation means votes are immediately active
        assertEq(locker.getVotes(alice), LOCK_AMOUNT);
        assertEq(locker.delegates(alice), alice);
    }

    function test_delegate_toAnotherAddress() public {
        vm.startPrank(alice);
        locker.lock(alice, LOCK_AMOUNT);
        locker.delegate(bob);
        vm.stopPrank();

        vm.roll(block.number + 1);
        assertEq(locker.getVotes(bob), LOCK_AMOUNT);
        assertEq(locker.getVotes(alice), 0);
    }

    function test_delegate_changeDelegateMovesVotes() public {
        vm.startPrank(alice);
        locker.lock(alice, LOCK_AMOUNT);
        locker.delegate(bob);
        vm.stopPrank();

        vm.roll(block.number + 1);
        assertEq(locker.getVotes(bob), LOCK_AMOUNT);

        vm.prank(alice);
        locker.delegate(charlie);

        vm.roll(block.number + 1);
        assertEq(locker.getVotes(bob), 0);
        assertEq(locker.getVotes(charlie), LOCK_AMOUNT);
    }

    // -------------------------------------------------------------------------
    // Voting units on lock
    // -------------------------------------------------------------------------

    function test_lock_updatesVotingPower() public {
        vm.startPrank(alice);
        locker.delegate(alice);
        locker.lock(alice, LOCK_AMOUNT);
        vm.stopPrank();

        assertEq(locker.getVotes(alice), LOCK_AMOUNT);
    }

    function test_lock_topUp_increasesVotingPower() public {
        vm.startPrank(alice);
        locker.delegate(alice);
        locker.lock(alice, LOCK_AMOUNT);
        locker.lock(alice, LOCK_AMOUNT);
        vm.stopPrank();

        assertEq(locker.getVotes(alice), LOCK_AMOUNT * 2);
    }

    // -------------------------------------------------------------------------
    // Voting power on unlock vs withdraw
    // -------------------------------------------------------------------------

    function test_unlock_removesVotingPower() public {
        vm.startPrank(alice);
        locker.delegate(alice);
        locker.lock(alice, LOCK_AMOUNT);
        locker.unlock();
        vm.stopPrank();

        assertEq(locker.getVotes(alice), 0);
    }

    function test_withdraw_removesVotingPower() public {
        vm.startPrank(alice);
        locker.delegate(alice);
        locker.lock(alice, LOCK_AMOUNT);
        locker.unlock();
        vm.stopPrank();

        vm.warp(block.timestamp + 14 days);

        vm.prank(alice);
        locker.withdraw(alice);

        assertEq(locker.getVotes(alice), 0);
    }

    // -------------------------------------------------------------------------
    // Historical checkpoints
    // -------------------------------------------------------------------------

    function test_getVotes_reflectsLockAndWithdraw() public {
        // Before lock: no votes
        assertEq(locker.getVotes(alice), 0);

        vm.startPrank(alice);
        locker.delegate(alice);
        locker.lock(alice, LOCK_AMOUNT);
        vm.stopPrank();

        // After lock: has votes
        assertEq(locker.getVotes(alice), LOCK_AMOUNT);

        // After unlock: votes removed
        vm.prank(alice);
        locker.unlock();
        assertEq(locker.getVotes(alice), 0);

        // After relock: votes restored
        vm.prank(alice);
        locker.relock();
        assertEq(locker.getVotes(alice), LOCK_AMOUNT);
    }

    function test_getPastTotalSupply_tracksLockedTokens() public {
        vm.roll(10);

        vm.startPrank(alice);
        locker.delegate(alice);
        locker.lock(alice, LOCK_AMOUNT);
        vm.stopPrank();

        vm.roll(20);

        assertEq(locker.getPastTotalSupply(10), LOCK_AMOUNT);

        // Bob locks
        vm.startPrank(bob);
        locker.delegate(bob);
        locker.lock(bob, LOCK_AMOUNT * 2);
        vm.stopPrank();

        vm.roll(30);

        assertEq(locker.getPastTotalSupply(20), LOCK_AMOUNT * 3);
        // Historical snapshot unchanged
        assertEq(locker.getPastTotalSupply(10), LOCK_AMOUNT);
    }

    // -------------------------------------------------------------------------
    // Multiple users
    // -------------------------------------------------------------------------

    function test_multipleUsers_independentVotingPower() public {
        vm.startPrank(alice);
        locker.delegate(alice);
        locker.lock(alice, LOCK_AMOUNT);
        vm.stopPrank();

        vm.startPrank(bob);
        locker.delegate(bob);
        locker.lock(bob, LOCK_AMOUNT * 2);
        vm.stopPrank();

        assertEq(locker.getVotes(alice), LOCK_AMOUNT);
        assertEq(locker.getVotes(bob), LOCK_AMOUNT * 2);
    }

    // -------------------------------------------------------------------------
    // Full lifecycle checkpoints
    // -------------------------------------------------------------------------

    function test_lockWithdrawRelock_checkpointsCorrect() public {
        vm.startPrank(alice);
        locker.delegate(alice);

        locker.lock(alice, LOCK_AMOUNT);
        assertEq(locker.getVotes(alice), LOCK_AMOUNT);

        locker.unlock();
        assertEq(locker.getVotes(alice), 0);

        vm.warp(block.timestamp + 14 days);
        locker.withdraw(alice);
        assertEq(locker.getVotes(alice), 0);

        locker.lock(alice, LOCK_AMOUNT * 2);
        assertEq(locker.getVotes(alice), LOCK_AMOUNT * 2);

        vm.stopPrank();
    }
}
