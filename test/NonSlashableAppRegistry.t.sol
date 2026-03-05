// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ILock2} from "../src/interfaces/ILock2.sol";
import {NonSlashableAppRegistry} from "../src/NonSlashableAppRegistry.sol";
import {YellowToken} from "../src/Token.sol";

contract NonSlashableAppRegistryTest is Test {
    NonSlashableAppRegistry vault;
    YellowToken token;

    address treasury = address(2);
    address alice = address(3);
    address bob = address(4);

    uint256 constant LOCK_AMOUNT = 1000 ether;

    function setUp() public {
        token = new YellowToken(treasury);
        vault = new NonSlashableAppRegistry(address(token), 14 days);

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
        vm.expectRevert(abi.encodeWithSelector(ILock2.InvalidAddress.selector));
        new NonSlashableAppRegistry(address(0), 14 days);
    }

    function test_constructor_revert_ifUnlockPeriodIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(ILock2.InvalidAmount.selector));
        new NonSlashableAppRegistry(address(token), 0);
    }

    function test_constructor_setsAsset() public view {
        assertEq(vault.asset(), address(token));
    }

    function test_constructor_setsUnlockPeriod() public view {
        assertEq(vault.UNLOCK_PERIOD(), 14 days);
    }

    // -------------------------------------------------------------------------
    // Initial state
    // -------------------------------------------------------------------------

    function test_initialState_idle() public view {
        assertEq(uint256(vault.lockStateOf(alice)), uint256(ILock2.LockState.Idle));
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

        assertEq(uint256(vault.lockStateOf(alice)), uint256(ILock2.LockState.Locked));
    }

    function test_lock_emitsLocked() public {
        vm.prank(alice);
        vm.expectEmit(true, false, false, true, address(vault));
        emit ILock2.Locked(alice, LOCK_AMOUNT, LOCK_AMOUNT);
        vault.lock(alice, LOCK_AMOUNT);
    }

    function test_lock_topUp() public {
        vm.startPrank(alice);
        vault.lock(alice, LOCK_AMOUNT);
        vault.lock(alice, LOCK_AMOUNT);
        vm.stopPrank();

        assertEq(vault.balanceOf(alice), LOCK_AMOUNT * 2);
    }

    function test_lock_revert_ifAmountIsZero() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ILock2.InvalidAmount.selector));
        vault.lock(alice, 0);
    }

    function test_lock_revert_ifAlreadyUnlocking() public {
        vm.startPrank(alice);
        vault.lock(alice, LOCK_AMOUNT);
        vault.unlock();

        vm.expectRevert(abi.encodeWithSelector(ILock2.AlreadyUnlocking.selector));
        vault.lock(alice, LOCK_AMOUNT);
        vm.stopPrank();
    }

    function test_lock_creditsTarget() public {
        vm.prank(alice);
        vault.lock(bob, LOCK_AMOUNT);

        assertEq(vault.balanceOf(bob), LOCK_AMOUNT);
        assertEq(vault.balanceOf(alice), 0);
    }

    function test_lock_debitsPayerNotTarget() public {
        uint256 aliceBalBefore = token.balanceOf(alice);

        vm.prank(alice);
        vault.lock(bob, LOCK_AMOUNT);

        assertEq(token.balanceOf(alice), aliceBalBefore - LOCK_AMOUNT);
        assertEq(token.balanceOf(bob), 10_000 ether);
    }

    function test_lock_revert_ifTargetAlreadyUnlocking() public {
        vm.prank(alice);
        vault.lock(alice, LOCK_AMOUNT);
        vm.prank(alice);
        vault.unlock();

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(ILock2.AlreadyUnlocking.selector));
        vault.lock(alice, LOCK_AMOUNT);
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

        assertEq(uint256(vault.lockStateOf(alice)), uint256(ILock2.LockState.Unlocking));
    }

    function test_unlock_emitsUnlockInitiated() public {
        vm.startPrank(alice);
        vault.lock(alice, LOCK_AMOUNT);

        uint256 expectedAvailableAt = block.timestamp + 14 days;
        vm.expectEmit(true, false, false, true, address(vault));
        emit ILock2.UnlockInitiated(alice, LOCK_AMOUNT, expectedAvailableAt);
        vault.unlock();
        vm.stopPrank();
    }

    function test_unlock_revert_ifIdle() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ILock2.NotLocked.selector));
        vault.unlock();
    }

    function test_unlock_revert_ifAlreadyUnlocking() public {
        vm.startPrank(alice);
        vault.lock(alice, LOCK_AMOUNT);
        vault.unlock();

        vm.expectRevert(abi.encodeWithSelector(ILock2.AlreadyUnlocking.selector));
        vault.unlock();
        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // relock()
    // -------------------------------------------------------------------------

    function test_relock_setsStateLocked() public {
        vm.startPrank(alice);
        vault.lock(alice, LOCK_AMOUNT);
        vault.unlock();
        vault.relock();
        vm.stopPrank();

        assertEq(uint256(vault.lockStateOf(alice)), uint256(ILock2.LockState.Locked));
    }

    function test_relock_clearsUnlockTimestamp() public {
        vm.startPrank(alice);
        vault.lock(alice, LOCK_AMOUNT);
        vault.unlock();
        vault.relock();
        vm.stopPrank();

        assertEq(vault.unlockTimestampOf(alice), 0);
    }

    function test_relock_emitsRelocked() public {
        vm.startPrank(alice);
        vault.lock(alice, LOCK_AMOUNT);
        vault.unlock();
        vm.stopPrank();

        vm.prank(alice);
        vm.expectEmit(true, false, false, true, address(vault));
        emit ILock2.Relocked(alice, LOCK_AMOUNT);
        vault.relock();
    }

    function test_relock_revert_ifNotUnlocking() public {
        vm.startPrank(alice);
        vault.lock(alice, LOCK_AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(ILock2.NotUnlocking.selector));
        vault.relock();
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
    }

    function test_withdraw_resetsStateToIdle() public {
        vm.startPrank(alice);
        vault.lock(alice, LOCK_AMOUNT);
        vault.unlock();
        vm.stopPrank();

        vm.warp(block.timestamp + 14 days);

        vm.prank(alice);
        vault.withdraw(alice);

        assertEq(uint256(vault.lockStateOf(alice)), uint256(ILock2.LockState.Idle));
    }

    function test_withdraw_emitsWithdrawn() public {
        vm.startPrank(alice);
        vault.lock(alice, LOCK_AMOUNT);
        vault.unlock();
        vm.stopPrank();

        vm.warp(block.timestamp + 14 days);

        vm.prank(alice);
        vm.expectEmit(true, false, false, true, address(vault));
        emit ILock2.Withdrawn(alice, LOCK_AMOUNT);
        vault.withdraw(alice);
    }

    function test_withdraw_revert_ifNotUnlocking() public {
        vm.startPrank(alice);
        vault.lock(alice, LOCK_AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(ILock2.NotUnlocking.selector));
        vault.withdraw(alice);
        vm.stopPrank();
    }

    function test_withdraw_revert_ifPeriodNotElapsed() public {
        vm.startPrank(alice);
        vault.lock(alice, LOCK_AMOUNT);
        vault.unlock();
        vm.stopPrank();

        uint256 availableAt = vault.unlockTimestampOf(alice);
        vm.warp(availableAt - 1);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ILock2.UnlockPeriodNotElapsed.selector, availableAt));
        vault.withdraw(alice);
    }

    function test_withdraw_sendsToDestination() public {
        vm.startPrank(alice);
        vault.lock(alice, LOCK_AMOUNT);
        vault.unlock();
        vm.stopPrank();

        vm.warp(block.timestamp + 14 days);

        uint256 bobBalBefore = token.balanceOf(bob);
        vm.prank(alice);
        vault.withdraw(bob);

        assertEq(token.balanceOf(bob), bobBalBefore + LOCK_AMOUNT);
        assertEq(vault.balanceOf(alice), 0);
    }

    // -------------------------------------------------------------------------
    // Full lifecycle
    // -------------------------------------------------------------------------

    function test_fullCycle_lockUnlockWithdraw() public {
        uint256 aliceBalBefore = token.balanceOf(alice);

        vm.prank(alice);
        vault.lock(alice, LOCK_AMOUNT);
        assertEq(uint256(vault.lockStateOf(alice)), uint256(ILock2.LockState.Locked));

        vm.prank(alice);
        vault.unlock();
        assertEq(uint256(vault.lockStateOf(alice)), uint256(ILock2.LockState.Unlocking));

        vm.warp(block.timestamp + 14 days);
        vm.prank(alice);
        vault.withdraw(alice);
        assertEq(uint256(vault.lockStateOf(alice)), uint256(ILock2.LockState.Idle));

        assertEq(token.balanceOf(alice), aliceBalBefore);
    }
}
