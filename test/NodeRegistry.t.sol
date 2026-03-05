// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ILock} from "../src/interfaces/ILock.sol";
import {NodeRegistry} from "../src/NodeRegistry.sol";
import {YellowToken} from "../src/Token.sol";

contract LockerTest is Test {
    NodeRegistry vault;
    YellowToken token;

    address treasury = address(2);
    address alice = address(3);
    address bob = address(4);

    uint256 constant LOCK_AMOUNT = 1000 ether;

    function setUp() public {
        token = new YellowToken(treasury);
        vault = new NodeRegistry(address(token), 14 days);

        // Fund alice and bob
        vm.startPrank(treasury);
        require(token.transfer(alice, 10_000 ether));
        require(token.transfer(bob, 10_000 ether));
        vm.stopPrank();

        // Approve vault for alice and bob
        vm.prank(alice);
        token.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        token.approve(address(vault), type(uint256).max);
    }

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    function test_constructor_revert_ifAssetIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(ILock.InvalidAddress.selector));
        new NodeRegistry(address(0), 14 days);
    }

    function test_constructor_revert_ifUnlockPeriodIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(ILock.InvalidAmount.selector));
        new NodeRegistry(address(token), 0);
    }

    function test_constructor_setsAsset() public view {
        assertEq(vault.asset(), address(token));
    }

    function test_constructor_setsAsset_immutable() public view {
        assertEq(vault.ASSET(), address(token));
    }

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    function test_unlockPeriod() public view {
        assertEq(vault.NODE_UNLOCK_PERIOD(), 14 days);
    }

    // -------------------------------------------------------------------------
    // Initial state
    // -------------------------------------------------------------------------

    function test_initialState_idle() public view {
        assertEq(uint256(vault.lockStateOf(alice)), uint256(ILock.LockState.Idle));
    }

    function test_initialState_zeroBalance() public view {
        assertEq(vault.balanceOf(alice), 0);
    }

    function test_initialState_zeroUnlockTimestamp() public view {
        assertEq(vault.unlockTimestampOf(alice), 0);
    }

    // -------------------------------------------------------------------------
    // lock()
    // -------------------------------------------------------------------------

    function test_lock_transfersTokens() public {
        uint256 balBefore = token.balanceOf(alice);

        vm.prank(alice);
        vault.lock(alice, LOCK_AMOUNT);

        assertEq(token.balanceOf(alice), balBefore - LOCK_AMOUNT);
        assertEq(token.balanceOf(address(vault)), LOCK_AMOUNT);
    }

    function test_lock_updatesBalance() public {
        vm.prank(alice);
        vault.lock(alice, LOCK_AMOUNT);

        assertEq(vault.balanceOf(alice), LOCK_AMOUNT);
    }

    function test_lock_setsStateLocked() public {
        vm.prank(alice);
        vault.lock(alice, LOCK_AMOUNT);

        assertEq(uint256(vault.lockStateOf(alice)), uint256(ILock.LockState.Locked));
    }

    function test_lock_emitsLocked() public {
        vm.prank(alice);
        vm.expectEmit(true, false, false, true, address(vault));
        emit ILock.Locked(alice, LOCK_AMOUNT, LOCK_AMOUNT);
        vault.lock(alice, LOCK_AMOUNT);
    }

    function test_lock_topUp() public {
        vm.startPrank(alice);
        vault.lock(alice, LOCK_AMOUNT);
        vault.lock(alice, LOCK_AMOUNT);
        vm.stopPrank();

        assertEq(vault.balanceOf(alice), LOCK_AMOUNT * 2);
    }

    function test_lock_topUp_emitsCumulativeBalance() public {
        vm.startPrank(alice);
        vault.lock(alice, LOCK_AMOUNT);

        vm.expectEmit(true, false, false, true, address(vault));
        emit ILock.Locked(alice, LOCK_AMOUNT, LOCK_AMOUNT * 2);
        vault.lock(alice, LOCK_AMOUNT);
        vm.stopPrank();
    }

    function test_lock_revert_ifAmountIsZero() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ILock.InvalidAmount.selector));
        vault.lock(alice, 0);
    }

    function test_lock_revert_ifAlreadyUnlocking() public {
        vm.startPrank(alice);
        vault.lock(alice, LOCK_AMOUNT);
        vault.unlock();

        vm.expectRevert(abi.encodeWithSelector(ILock.AlreadyUnlocking.selector));
        vault.lock(alice, LOCK_AMOUNT);
        vm.stopPrank();
    }

    function test_lock_independentPerUser() public {
        vm.prank(alice);
        vault.lock(alice, LOCK_AMOUNT);

        vm.prank(bob);
        vault.lock(bob, LOCK_AMOUNT * 2);

        assertEq(vault.balanceOf(alice), LOCK_AMOUNT);
        assertEq(vault.balanceOf(bob), LOCK_AMOUNT * 2);
    }

    function test_lock_fuzz(uint256 amount) public {
        amount = bound(amount, 1, token.balanceOf(alice));

        vm.prank(alice);
        vault.lock(alice, amount);

        assertEq(vault.balanceOf(alice), amount);
    }

    // -------------------------------------------------------------------------
    // unlock()
    // -------------------------------------------------------------------------

    function test_unlock_setsUnlockTimestamp() public {
        vm.startPrank(alice);
        vault.lock(alice, LOCK_AMOUNT);
        vault.unlock();
        vm.stopPrank();

        assertEq(vault.unlockTimestampOf(alice), block.timestamp + 14 days);
    }

    function test_unlock_setsStateUnlocking() public {
        vm.startPrank(alice);
        vault.lock(alice, LOCK_AMOUNT);
        vault.unlock();
        vm.stopPrank();

        assertEq(uint256(vault.lockStateOf(alice)), uint256(ILock.LockState.Unlocking));
    }

    function test_unlock_emitsUnlockInitiated() public {
        vm.startPrank(alice);
        vault.lock(alice, LOCK_AMOUNT);

        uint256 expectedAvailableAt = block.timestamp + 14 days;
        vm.expectEmit(true, false, false, true, address(vault));
        emit ILock.UnlockInitiated(alice, LOCK_AMOUNT, expectedAvailableAt);
        vault.unlock();
        vm.stopPrank();
    }

    function test_unlock_revert_ifIdle() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ILock.NotLocked.selector));
        vault.unlock();
    }

    function test_unlock_revert_ifAlreadyUnlocking() public {
        vm.startPrank(alice);
        vault.lock(alice, LOCK_AMOUNT);
        vault.unlock();

        vm.expectRevert(abi.encodeWithSelector(ILock.AlreadyUnlocking.selector));
        vault.unlock();
        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // withdraw()
    // -------------------------------------------------------------------------

    function test_withdraw_transfersTokensBack() public {
        vm.startPrank(alice);
        vault.lock(alice, LOCK_AMOUNT);
        vault.unlock();
        vm.stopPrank();

        vm.warp(block.timestamp + 14 days);

        uint256 balBefore = token.balanceOf(alice);
        vm.prank(alice);
        vault.withdraw(alice);

        assertEq(token.balanceOf(alice), balBefore + LOCK_AMOUNT);
        assertEq(token.balanceOf(address(vault)), 0);
    }

    function test_withdraw_resetsBalanceToZero() public {
        vm.startPrank(alice);
        vault.lock(alice, LOCK_AMOUNT);
        vault.unlock();
        vm.stopPrank();

        vm.warp(block.timestamp + 14 days);

        vm.prank(alice);
        vault.withdraw(alice);

        assertEq(vault.balanceOf(alice), 0);
    }

    function test_withdraw_resetsUnlockTimestampToZero() public {
        vm.startPrank(alice);
        vault.lock(alice, LOCK_AMOUNT);
        vault.unlock();
        vm.stopPrank();

        vm.warp(block.timestamp + 14 days);

        vm.prank(alice);
        vault.withdraw(alice);

        assertEq(vault.unlockTimestampOf(alice), 0);
    }

    function test_withdraw_setsStateIdle() public {
        vm.startPrank(alice);
        vault.lock(alice, LOCK_AMOUNT);
        vault.unlock();
        vm.stopPrank();

        vm.warp(block.timestamp + 14 days);

        vm.prank(alice);
        vault.withdraw(alice);

        assertEq(uint256(vault.lockStateOf(alice)), uint256(ILock.LockState.Idle));
    }

    function test_withdraw_emitsWithdrawn() public {
        vm.startPrank(alice);
        vault.lock(alice, LOCK_AMOUNT);
        vault.unlock();
        vm.stopPrank();

        vm.warp(block.timestamp + 14 days);

        vm.prank(alice);
        vm.expectEmit(true, false, false, true, address(vault));
        emit ILock.Withdrawn(alice, LOCK_AMOUNT);
        vault.withdraw(alice);
    }

    function test_withdraw_revert_ifNotUnlocking() public {
        vm.startPrank(alice);
        vault.lock(alice, LOCK_AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(ILock.NotUnlocking.selector));
        vault.withdraw(alice);
        vm.stopPrank();
    }

    function test_withdraw_revert_ifIdle() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ILock.NotUnlocking.selector));
        vault.withdraw(alice);
    }

    function test_withdraw_revert_ifPeriodNotElapsed() public {
        vm.startPrank(alice);
        vault.lock(alice, LOCK_AMOUNT);
        vault.unlock();
        vm.stopPrank();

        uint256 availableAt = vault.unlockTimestampOf(alice);
        vm.warp(availableAt - 1);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ILock.UnlockPeriodNotElapsed.selector, availableAt));
        vault.withdraw(alice);
    }

    function test_withdraw_exactlyAtUnlockTimestamp() public {
        vm.startPrank(alice);
        vault.lock(alice, LOCK_AMOUNT);
        vault.unlock();
        vm.stopPrank();

        vm.warp(vault.unlockTimestampOf(alice));

        vm.prank(alice);
        vault.withdraw(alice);

        assertEq(vault.balanceOf(alice), 0);
    }

    // -------------------------------------------------------------------------
    // Full lifecycle
    // -------------------------------------------------------------------------

    function test_fullCycle_lockUnlockWithdraw() public {
        uint256 aliceBalBefore = token.balanceOf(alice);

        // Lock
        vm.prank(alice);
        vault.lock(alice, LOCK_AMOUNT);
        assertEq(uint256(vault.lockStateOf(alice)), uint256(ILock.LockState.Locked));

        // Unlock
        vm.prank(alice);
        vault.unlock();
        assertEq(uint256(vault.lockStateOf(alice)), uint256(ILock.LockState.Unlocking));

        // Withdraw
        vm.warp(block.timestamp + 14 days);
        vm.prank(alice);
        vault.withdraw(alice);
        assertEq(uint256(vault.lockStateOf(alice)), uint256(ILock.LockState.Idle));

        assertEq(token.balanceOf(alice), aliceBalBefore);
    }

    function test_fullCycle_canRelockAfterWithdraw() public {
        vm.startPrank(alice);

        // First cycle
        vault.lock(alice, LOCK_AMOUNT);
        vault.unlock();
        vm.warp(block.timestamp + 14 days);
        vault.withdraw(alice);

        // Second cycle
        vault.lock(alice, LOCK_AMOUNT);
        assertEq(uint256(vault.lockStateOf(alice)), uint256(ILock.LockState.Locked));
        assertEq(vault.balanceOf(alice), LOCK_AMOUNT);

        vm.stopPrank();
    }

    function test_fullCycle_multipleUsersIndependent() public {
        // Alice locks
        vm.prank(alice);
        vault.lock(alice, LOCK_AMOUNT);

        // Bob locks
        vm.prank(bob);
        vault.lock(bob, LOCK_AMOUNT * 2);

        // Alice unlocks
        vm.prank(alice);
        vault.unlock();

        // Bob is still locked
        assertEq(uint256(vault.lockStateOf(bob)), uint256(ILock.LockState.Locked));

        // Warp and alice withdraws
        vm.warp(block.timestamp + 14 days);
        vm.prank(alice);
        vault.withdraw(alice);

        // Bob's balance is untouched
        assertEq(vault.balanceOf(bob), LOCK_AMOUNT * 2);
        assertEq(uint256(vault.lockStateOf(bob)), uint256(ILock.LockState.Locked));
    }
}
