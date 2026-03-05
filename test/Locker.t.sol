// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ILock} from "../src/interfaces/ILock.sol";
import {YellowToken} from "../src/Token.sol";

/// @dev Abstract base for testing any ILock implementation.
///      Subcontracts must implement _createVault() and _vault().
abstract contract LockerTestBase is Test {
    YellowToken token;

    address treasury = makeAddr("treasury");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint256 constant INITIAL_BALANCE = 10_000 ether;
    uint256 constant LOCK_AMOUNT = 1000 ether;
    uint256 constant UNLOCK_PERIOD = 14 days;

    function _vault() internal view virtual returns (ILock);
    function _vaultAddress() internal view virtual returns (address);

    /// @dev Subclasses must set `token` and deploy their vault before calling super.setUp().
    function setUp() public virtual {
        // Fund alice and bob
        vm.startPrank(treasury);
        require(token.transfer(alice, INITIAL_BALANCE));
        require(token.transfer(bob, INITIAL_BALANCE));
        vm.stopPrank();

        // Approve vault for alice and bob
        vm.prank(alice);
        token.approve(_vaultAddress(), type(uint256).max);
        vm.prank(bob);
        token.approve(_vaultAddress(), type(uint256).max);
    }

    // -------------------------------------------------------------------------
    // Initial state
    // -------------------------------------------------------------------------

    function test_initialState_idle() public view {
        assertEq(uint256(_vault().lockStateOf(alice)), uint256(ILock.LockState.Idle));
    }

    function test_initialState_zeroBalance() public view {
        assertEq(_vault().balanceOf(alice), 0);
    }

    function test_initialState_zeroUnlockTimestamp() public view {
        assertEq(_vault().unlockTimestampOf(alice), 0);
    }

    // -------------------------------------------------------------------------
    // lock()
    // -------------------------------------------------------------------------

    function test_lock_transfersTokens() public {
        uint256 balBefore = token.balanceOf(alice);

        vm.prank(alice);
        _vault().lock(alice, LOCK_AMOUNT);

        assertEq(token.balanceOf(alice), balBefore - LOCK_AMOUNT);
        assertEq(token.balanceOf(_vaultAddress()), LOCK_AMOUNT);
    }

    function test_lock_updatesBalance() public {
        vm.prank(alice);
        _vault().lock(alice, LOCK_AMOUNT);

        assertEq(_vault().balanceOf(alice), LOCK_AMOUNT);
    }

    function test_lock_setsStateLocked() public {
        vm.prank(alice);
        _vault().lock(alice, LOCK_AMOUNT);

        assertEq(uint256(_vault().lockStateOf(alice)), uint256(ILock.LockState.Locked));
    }

    function test_lock_emitsLocked() public {
        vm.prank(alice);
        vm.expectEmit(true, false, false, true, _vaultAddress());
        emit ILock.Locked(alice, LOCK_AMOUNT, LOCK_AMOUNT);
        _vault().lock(alice, LOCK_AMOUNT);
    }

    function test_lock_topUp() public {
        vm.startPrank(alice);
        _vault().lock(alice, LOCK_AMOUNT);
        _vault().lock(alice, LOCK_AMOUNT);
        vm.stopPrank();

        assertEq(_vault().balanceOf(alice), LOCK_AMOUNT * 2);
    }

    function test_lock_topUp_emitsCumulativeBalance() public {
        vm.startPrank(alice);
        _vault().lock(alice, LOCK_AMOUNT);

        vm.expectEmit(true, false, false, true, _vaultAddress());
        emit ILock.Locked(alice, LOCK_AMOUNT, LOCK_AMOUNT * 2);
        _vault().lock(alice, LOCK_AMOUNT);
        vm.stopPrank();
    }

    function test_lock_revert_ifAmountIsZero() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ILock.InvalidAmount.selector));
        _vault().lock(alice, 0);
    }

    function test_lock_revert_ifAlreadyUnlocking() public {
        vm.startPrank(alice);
        _vault().lock(alice, LOCK_AMOUNT);
        _vault().unlock();

        vm.expectRevert(abi.encodeWithSelector(ILock.AlreadyUnlocking.selector));
        _vault().lock(alice, LOCK_AMOUNT);
        vm.stopPrank();
    }

    function test_lock_creditsTarget() public {
        vm.prank(alice);
        _vault().lock(bob, LOCK_AMOUNT);

        assertEq(_vault().balanceOf(bob), LOCK_AMOUNT);
        assertEq(_vault().balanceOf(alice), 0);
    }

    function test_lock_debitsPayerNotTarget() public {
        vm.prank(alice);
        _vault().lock(bob, LOCK_AMOUNT);

        assertEq(token.balanceOf(alice), INITIAL_BALANCE - LOCK_AMOUNT);
        assertEq(token.balanceOf(bob), INITIAL_BALANCE);
    }

    function test_lock_revert_ifTargetAlreadyUnlocking() public {
        vm.startPrank(alice);
        _vault().lock(alice, LOCK_AMOUNT);
        _vault().unlock();
        vm.stopPrank();

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(ILock.AlreadyUnlocking.selector));
        _vault().lock(alice, LOCK_AMOUNT);
    }

    function test_lock_independentPerUser() public {
        vm.prank(alice);
        _vault().lock(alice, LOCK_AMOUNT);

        vm.prank(bob);
        _vault().lock(bob, LOCK_AMOUNT * 2);

        assertEq(_vault().balanceOf(alice), LOCK_AMOUNT);
        assertEq(_vault().balanceOf(bob), LOCK_AMOUNT * 2);
    }

    function test_lock_fuzz(uint256 amount) public {
        amount = bound(amount, 1, token.balanceOf(alice));

        vm.prank(alice);
        _vault().lock(alice, amount);

        assertEq(_vault().balanceOf(alice), amount);
    }

    // -------------------------------------------------------------------------
    // unlock()
    // -------------------------------------------------------------------------

    function test_unlock_setsUnlockTimestamp() public {
        vm.startPrank(alice);
        _vault().lock(alice, LOCK_AMOUNT);
        _vault().unlock();
        vm.stopPrank();

        assertEq(_vault().unlockTimestampOf(alice), block.timestamp + UNLOCK_PERIOD);
    }

    function test_unlock_setsStateUnlocking() public {
        vm.startPrank(alice);
        _vault().lock(alice, LOCK_AMOUNT);
        _vault().unlock();
        vm.stopPrank();

        assertEq(uint256(_vault().lockStateOf(alice)), uint256(ILock.LockState.Unlocking));
    }

    function test_unlock_emitsUnlockInitiated() public {
        vm.startPrank(alice);
        _vault().lock(alice, LOCK_AMOUNT);

        uint256 expectedAvailableAt = block.timestamp + UNLOCK_PERIOD;
        vm.expectEmit(true, false, false, true, _vaultAddress());
        emit ILock.UnlockInitiated(alice, LOCK_AMOUNT, expectedAvailableAt);
        _vault().unlock();
        vm.stopPrank();
    }

    function test_unlock_revert_ifIdle() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ILock.NotLocked.selector));
        _vault().unlock();
    }

    function test_unlock_revert_ifAlreadyUnlocking() public {
        vm.startPrank(alice);
        _vault().lock(alice, LOCK_AMOUNT);
        _vault().unlock();

        vm.expectRevert(abi.encodeWithSelector(ILock.AlreadyUnlocking.selector));
        _vault().unlock();
        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // relock()
    // -------------------------------------------------------------------------

    function test_relock_success() public {
        vm.startPrank(alice);
        _vault().lock(alice, LOCK_AMOUNT);
        _vault().unlock();
        _vault().relock();
        vm.stopPrank();

        assertEq(uint256(_vault().lockStateOf(alice)), uint256(ILock.LockState.Locked));
        assertEq(_vault().unlockTimestampOf(alice), 0);
    }

    function test_relock_emitsRelocked() public {
        vm.startPrank(alice);
        _vault().lock(alice, LOCK_AMOUNT);
        _vault().unlock();

        vm.expectEmit(true, false, false, true, _vaultAddress());
        emit ILock.Relocked(alice, LOCK_AMOUNT);
        _vault().relock();
        vm.stopPrank();
    }

    function test_relock_revert_ifNotUnlocking() public {
        vm.startPrank(bob);
        _vault().lock(bob, LOCK_AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(ILock.NotUnlocking.selector));
        _vault().relock();
        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // withdraw()
    // -------------------------------------------------------------------------

    function test_withdraw_transfersTokensBack() public {
        vm.startPrank(alice);
        _vault().lock(alice, LOCK_AMOUNT);
        _vault().unlock();
        vm.stopPrank();

        vm.warp(block.timestamp + UNLOCK_PERIOD);

        uint256 balBefore = token.balanceOf(alice);
        vm.prank(alice);
        _vault().withdraw(alice);

        assertEq(token.balanceOf(alice), balBefore + LOCK_AMOUNT);
        assertEq(token.balanceOf(_vaultAddress()), 0);
    }

    function test_withdraw_resetsBalanceToZero() public {
        vm.startPrank(alice);
        _vault().lock(alice, LOCK_AMOUNT);
        _vault().unlock();
        vm.stopPrank();

        vm.warp(block.timestamp + UNLOCK_PERIOD);

        vm.prank(alice);
        _vault().withdraw(alice);

        assertEq(_vault().balanceOf(alice), 0);
    }

    function test_withdraw_resetsUnlockTimestampToZero() public {
        vm.startPrank(alice);
        _vault().lock(alice, LOCK_AMOUNT);
        _vault().unlock();
        vm.stopPrank();

        vm.warp(block.timestamp + UNLOCK_PERIOD);

        vm.prank(alice);
        _vault().withdraw(alice);

        assertEq(_vault().unlockTimestampOf(alice), 0);
    }

    function test_withdraw_setsStateIdle() public {
        vm.startPrank(alice);
        _vault().lock(alice, LOCK_AMOUNT);
        _vault().unlock();
        vm.stopPrank();

        vm.warp(block.timestamp + UNLOCK_PERIOD);

        vm.prank(alice);
        _vault().withdraw(alice);

        assertEq(uint256(_vault().lockStateOf(alice)), uint256(ILock.LockState.Idle));
    }

    function test_withdraw_emitsWithdrawn() public {
        vm.startPrank(alice);
        _vault().lock(alice, LOCK_AMOUNT);
        _vault().unlock();
        vm.stopPrank();

        vm.warp(block.timestamp + UNLOCK_PERIOD);

        vm.prank(alice);
        vm.expectEmit(true, false, false, true, _vaultAddress());
        emit ILock.Withdrawn(alice, LOCK_AMOUNT);
        _vault().withdraw(alice);
    }

    function test_withdraw_revert_ifNotUnlocking() public {
        vm.startPrank(alice);
        _vault().lock(alice, LOCK_AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(ILock.NotUnlocking.selector));
        _vault().withdraw(alice);
        vm.stopPrank();
    }

    function test_withdraw_revert_ifIdle() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ILock.NotUnlocking.selector));
        _vault().withdraw(alice);
    }

    function test_withdraw_revert_ifPeriodNotElapsed() public {
        vm.startPrank(alice);
        _vault().lock(alice, LOCK_AMOUNT);
        _vault().unlock();
        vm.stopPrank();

        uint256 availableAt = _vault().unlockTimestampOf(alice);
        vm.warp(availableAt - 1);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ILock.UnlockPeriodNotElapsed.selector, availableAt));
        _vault().withdraw(alice);
    }

    function test_withdraw_exactlyAtUnlockTimestamp() public {
        vm.startPrank(alice);
        _vault().lock(alice, LOCK_AMOUNT);
        _vault().unlock();
        vm.stopPrank();

        vm.warp(_vault().unlockTimestampOf(alice));

        vm.prank(alice);
        _vault().withdraw(alice);

        assertEq(_vault().balanceOf(alice), 0);
    }

    function test_withdraw_sendsToDestination() public {
        vm.startPrank(alice);
        _vault().lock(alice, LOCK_AMOUNT);
        _vault().unlock();
        vm.stopPrank();

        vm.warp(block.timestamp + UNLOCK_PERIOD);

        uint256 bobBalBefore = token.balanceOf(bob);
        vm.prank(alice);
        _vault().withdraw(bob);

        assertEq(token.balanceOf(bob), bobBalBefore + LOCK_AMOUNT);
        assertEq(_vault().balanceOf(alice), 0);
    }

    // -------------------------------------------------------------------------
    // Full lifecycle
    // -------------------------------------------------------------------------

    function test_fullCycle_lockUnlockWithdraw() public {
        uint256 aliceBalBefore = token.balanceOf(alice);

        vm.prank(alice);
        _vault().lock(alice, LOCK_AMOUNT);
        assertEq(uint256(_vault().lockStateOf(alice)), uint256(ILock.LockState.Locked));

        vm.prank(alice);
        _vault().unlock();
        assertEq(uint256(_vault().lockStateOf(alice)), uint256(ILock.LockState.Unlocking));

        vm.warp(block.timestamp + UNLOCK_PERIOD);
        vm.prank(alice);
        _vault().withdraw(alice);
        assertEq(uint256(_vault().lockStateOf(alice)), uint256(ILock.LockState.Idle));

        assertEq(token.balanceOf(alice), aliceBalBefore);
    }

    function test_fullCycle_canRelockAfterWithdraw() public {
        vm.startPrank(alice);

        _vault().lock(alice, LOCK_AMOUNT);
        _vault().unlock();
        vm.warp(block.timestamp + UNLOCK_PERIOD);
        _vault().withdraw(alice);

        _vault().lock(alice, LOCK_AMOUNT);
        assertEq(uint256(_vault().lockStateOf(alice)), uint256(ILock.LockState.Locked));
        assertEq(_vault().balanceOf(alice), LOCK_AMOUNT);

        vm.stopPrank();
    }

    function test_fullCycle_multipleUsersIndependent() public {
        vm.prank(alice);
        _vault().lock(alice, LOCK_AMOUNT);

        vm.prank(bob);
        _vault().lock(bob, LOCK_AMOUNT * 2);

        vm.prank(alice);
        _vault().unlock();

        assertEq(uint256(_vault().lockStateOf(bob)), uint256(ILock.LockState.Locked));

        vm.warp(block.timestamp + UNLOCK_PERIOD);
        vm.prank(alice);
        _vault().withdraw(alice);

        assertEq(_vault().balanceOf(bob), LOCK_AMOUNT * 2);
        assertEq(uint256(_vault().lockStateOf(bob)), uint256(ILock.LockState.Locked));
    }
}
