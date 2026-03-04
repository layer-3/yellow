// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ILock} from "../src/interfaces/ILock.sol";
import {ISlash} from "../src/interfaces/ISlash.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {AppRegistry} from "../src/AppRegistry.sol";
import {YellowToken} from "../src/Token.sol";

contract AppRegistryTest is Test {
    AppRegistry vault;
    YellowToken token;

    address treasury = address(2);
    address alice = address(3);
    address bob = address(4);
    address admin = address(5);
    address adjudicator = address(6);
    address adjudicator2 = address(7);

    bytes32 ADJUDICATOR_ROLE;
    bytes32 DEFAULT_ADMIN_ROLE;

    uint256 constant LOCK_AMOUNT = 1000 ether;

    function setUp() public {
        token = new YellowToken(treasury);
        vault = new AppRegistry(address(token), 14 days, admin);

        // Cache role constants to avoid view calls consuming vm.prank
        ADJUDICATOR_ROLE = vault.ADJUDICATOR_ROLE();
        DEFAULT_ADMIN_ROLE = vault.DEFAULT_ADMIN_ROLE();

        // Grant adjudicator role
        vm.prank(admin);
        vault.grantRole(ADJUDICATOR_ROLE, adjudicator);

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
        new AppRegistry(address(0), 14 days, admin);
    }

    function test_constructor_revert_ifAdminIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(ILock.InvalidAddress.selector));
        new AppRegistry(address(token), 14 days, address(0));
    }

    function test_constructor_revert_ifUnlockPeriodIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(ILock.InvalidAmount.selector));
        new AppRegistry(address(token), 0, admin);
    }

    function test_constructor_setsAsset() public view {
        assertEq(vault.asset(), address(token));
    }

    function test_constructor_setsUnlockPeriod() public view {
        assertEq(vault.UNLOCK_PERIOD(), 14 days);
    }

    function test_constructor_grantsAdminRole() public view {
        assertTrue(vault.hasRole(DEFAULT_ADMIN_ROLE, admin));
    }

    // -------------------------------------------------------------------------
    // Access control — role management
    // -------------------------------------------------------------------------

    function test_admin_canGrantAdjudicatorRole() public {
        vm.prank(admin);
        vault.grantRole(ADJUDICATOR_ROLE, adjudicator2);

        assertTrue(vault.hasRole(ADJUDICATOR_ROLE, adjudicator2));
    }

    function test_admin_canRevokeAdjudicatorRole() public {
        vm.prank(admin);
        vault.revokeRole(ADJUDICATOR_ROLE, adjudicator);

        assertFalse(vault.hasRole(ADJUDICATOR_ROLE, adjudicator));
    }

    function test_nonAdmin_cannotGrantAdjudicatorRole() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, DEFAULT_ADMIN_ROLE)
        );
        vault.grantRole(ADJUDICATOR_ROLE, alice);
    }

    function test_multipleAdjudicators_canSlash() public {
        // Grant second adjudicator
        vm.prank(admin);
        vault.grantRole(ADJUDICATOR_ROLE, adjudicator2);

        vm.prank(alice);
        vault.lock(LOCK_AMOUNT);

        // Both adjudicators can slash
        vm.prank(adjudicator);
        vault.slash(alice, 100 ether);

        vm.prank(adjudicator2);
        vault.slash(alice, 100 ether);

        assertEq(vault.balanceOf(alice), LOCK_AMOUNT - 200 ether);
    }

    function test_revokedAdjudicator_cannotSlash() public {
        vm.prank(alice);
        vault.lock(LOCK_AMOUNT);

        vm.prank(admin);
        vault.revokeRole(ADJUDICATOR_ROLE, adjudicator);

        vm.prank(adjudicator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, adjudicator, ADJUDICATOR_ROLE
            )
        );
        vault.slash(alice, 100 ether);
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
        vault.lock(LOCK_AMOUNT);

        assertEq(token.balanceOf(alice), balBefore - LOCK_AMOUNT);
        assertEq(token.balanceOf(address(vault)), LOCK_AMOUNT);
    }

    function test_lock_updatesBalance() public {
        vm.prank(alice);
        vault.lock(LOCK_AMOUNT);

        assertEq(vault.balanceOf(alice), LOCK_AMOUNT);
    }

    function test_lock_setsStateLocked() public {
        vm.prank(alice);
        vault.lock(LOCK_AMOUNT);

        assertEq(uint256(vault.lockStateOf(alice)), uint256(ILock.LockState.Locked));
    }

    function test_lock_emitsLocked() public {
        vm.prank(alice);
        vm.expectEmit(true, false, false, true, address(vault));
        emit ILock.Locked(alice, LOCK_AMOUNT);
        vault.lock(LOCK_AMOUNT);
    }

    function test_lock_topUp() public {
        vm.startPrank(alice);
        vault.lock(LOCK_AMOUNT);
        vault.lock(LOCK_AMOUNT);
        vm.stopPrank();

        assertEq(vault.balanceOf(alice), LOCK_AMOUNT * 2);
    }

    function test_lock_revert_ifAmountIsZero() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ILock.InvalidAmount.selector));
        vault.lock(0);
    }

    function test_lock_revert_ifAlreadyUnlocking() public {
        vm.startPrank(alice);
        vault.lock(LOCK_AMOUNT);
        vault.unlock();

        vm.expectRevert(abi.encodeWithSelector(ILock.AlreadyUnlocking.selector));
        vault.lock(LOCK_AMOUNT);
        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // unlock()
    // -------------------------------------------------------------------------

    function test_unlock_setsUnlockTimestamp() public {
        vm.startPrank(alice);
        vault.lock(LOCK_AMOUNT);
        vault.unlock();
        vm.stopPrank();

        assertEq(vault.unlockTimestampOf(alice), block.timestamp + 14 days);
    }

    function test_unlock_setsStateUnlocking() public {
        vm.startPrank(alice);
        vault.lock(LOCK_AMOUNT);
        vault.unlock();
        vm.stopPrank();

        assertEq(uint256(vault.lockStateOf(alice)), uint256(ILock.LockState.Unlocking));
    }

    function test_unlock_emitsUnlockInitiated() public {
        vm.startPrank(alice);
        vault.lock(LOCK_AMOUNT);

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
        vault.lock(LOCK_AMOUNT);
        vault.unlock();

        vm.expectRevert(abi.encodeWithSelector(ILock.AlreadyUnlocking.selector));
        vault.unlock();
        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // relock()
    // -------------------------------------------------------------------------

    function test_relock_setsStateLocked() public {
        vm.startPrank(alice);
        vault.lock(LOCK_AMOUNT);
        vault.unlock();
        vault.relock();
        vm.stopPrank();

        assertEq(uint256(vault.lockStateOf(alice)), uint256(ILock.LockState.Locked));
    }

    function test_relock_clearsUnlockTimestamp() public {
        vm.startPrank(alice);
        vault.lock(LOCK_AMOUNT);
        vault.unlock();
        vault.relock();
        vm.stopPrank();

        assertEq(vault.unlockTimestampOf(alice), 0);
    }

    function test_relock_emitsRelocked() public {
        vm.startPrank(alice);
        vault.lock(LOCK_AMOUNT);
        vault.unlock();
        vm.stopPrank();

        vm.prank(alice);
        vm.expectEmit(true, false, false, true, address(vault));
        emit ILock.Relocked(alice, LOCK_AMOUNT);
        vault.relock();
    }

    function test_relock_revert_ifNotUnlocking() public {
        vm.startPrank(alice);
        vault.lock(LOCK_AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(ILock.NotUnlocking.selector));
        vault.relock();
        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // withdraw()
    // -------------------------------------------------------------------------

    function test_withdraw_transfersTokensBack() public {
        vm.startPrank(alice);
        vault.lock(LOCK_AMOUNT);
        vault.unlock();
        vm.stopPrank();

        vm.warp(block.timestamp + 14 days);

        uint256 balBefore = token.balanceOf(alice);
        vm.prank(alice);
        vault.withdraw();

        assertEq(token.balanceOf(alice), balBefore + LOCK_AMOUNT);
    }

    function test_withdraw_resetsStateToIdle() public {
        vm.startPrank(alice);
        vault.lock(LOCK_AMOUNT);
        vault.unlock();
        vm.stopPrank();

        vm.warp(block.timestamp + 14 days);

        vm.prank(alice);
        vault.withdraw();

        assertEq(uint256(vault.lockStateOf(alice)), uint256(ILock.LockState.Idle));
    }

    function test_withdraw_emitsWithdrawn() public {
        vm.startPrank(alice);
        vault.lock(LOCK_AMOUNT);
        vault.unlock();
        vm.stopPrank();

        vm.warp(block.timestamp + 14 days);

        vm.prank(alice);
        vm.expectEmit(true, false, false, true, address(vault));
        emit ILock.Withdrawn(alice, LOCK_AMOUNT);
        vault.withdraw();
    }

    function test_withdraw_revert_ifNotUnlocking() public {
        vm.startPrank(alice);
        vault.lock(LOCK_AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(ILock.NotUnlocking.selector));
        vault.withdraw();
        vm.stopPrank();
    }

    function test_withdraw_revert_ifPeriodNotElapsed() public {
        vm.startPrank(alice);
        vault.lock(LOCK_AMOUNT);
        vault.unlock();
        vm.stopPrank();

        uint256 availableAt = vault.unlockTimestampOf(alice);
        vm.warp(availableAt - 1);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ILock.UnlockPeriodNotElapsed.selector, availableAt));
        vault.withdraw();
    }

    // -------------------------------------------------------------------------
    // Full lifecycle
    // -------------------------------------------------------------------------

    function test_fullCycle_lockUnlockWithdraw() public {
        uint256 aliceBalBefore = token.balanceOf(alice);

        vm.prank(alice);
        vault.lock(LOCK_AMOUNT);
        assertEq(uint256(vault.lockStateOf(alice)), uint256(ILock.LockState.Locked));

        vm.prank(alice);
        vault.unlock();
        assertEq(uint256(vault.lockStateOf(alice)), uint256(ILock.LockState.Unlocking));

        vm.warp(block.timestamp + 14 days);
        vm.prank(alice);
        vault.withdraw();
        assertEq(uint256(vault.lockStateOf(alice)), uint256(ILock.LockState.Idle));

        assertEq(token.balanceOf(alice), aliceBalBefore);
    }

    // -------------------------------------------------------------------------
    // Slash — access control
    // -------------------------------------------------------------------------

    function test_slash_revert_ifNotAdjudicator() public {
        vm.prank(alice);
        vault.lock(LOCK_AMOUNT);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, ADJUDICATOR_ROLE)
        );
        vault.slash(alice, 100 ether);
    }

    function test_slash_revert_ifUserHasNoBalance() public {
        vm.prank(adjudicator);
        vm.expectRevert(abi.encodeWithSelector(ISlash.InsufficientBalance.selector));
        vault.slash(alice, 100 ether);
    }

    function test_slash_revert_ifAmountExceedsBalance() public {
        vm.prank(alice);
        vault.lock(LOCK_AMOUNT);

        vm.prank(adjudicator);
        vm.expectRevert(abi.encodeWithSelector(ISlash.InsufficientBalance.selector));
        vault.slash(alice, LOCK_AMOUNT + 1);
    }

    // -------------------------------------------------------------------------
    // Slash — while Locked
    // -------------------------------------------------------------------------

    function test_slash_locked_partialSlash_reducesBalance() public {
        vm.prank(alice);
        vault.lock(LOCK_AMOUNT);

        uint256 slashAmount = 300 ether;
        vm.prank(adjudicator);
        vault.slash(alice, slashAmount);

        assertEq(vault.balanceOf(alice), LOCK_AMOUNT - slashAmount);
        assertEq(uint256(vault.lockStateOf(alice)), uint256(ILock.LockState.Locked));
    }

    function test_slash_locked_partialSlash_transfersToCaller() public {
        vm.prank(alice);
        vault.lock(LOCK_AMOUNT);

        uint256 slashAmount = 300 ether;
        uint256 adjBalBefore = token.balanceOf(adjudicator);

        vm.prank(adjudicator);
        vault.slash(alice, slashAmount);

        assertEq(token.balanceOf(adjudicator), adjBalBefore + slashAmount);
    }

    function test_slash_locked_fullSlash_resetsToIdle() public {
        vm.prank(alice);
        vault.lock(LOCK_AMOUNT);

        vm.prank(adjudicator);
        vault.slash(alice, LOCK_AMOUNT);

        assertEq(vault.balanceOf(alice), 0);
        assertEq(uint256(vault.lockStateOf(alice)), uint256(ILock.LockState.Idle));
    }

    function test_slash_locked_emitsSlashed() public {
        vm.prank(alice);
        vault.lock(LOCK_AMOUNT);

        uint256 slashAmount = 500 ether;
        vm.prank(adjudicator);
        vm.expectEmit(true, true, false, true, address(vault));
        emit ISlash.Slashed(alice, slashAmount, adjudicator);
        vault.slash(alice, slashAmount);
    }

    // -------------------------------------------------------------------------
    // Slash — while Unlocking
    // -------------------------------------------------------------------------

    function test_slash_unlocking_partialSlash_remainsUnlocking() public {
        vm.startPrank(alice);
        vault.lock(LOCK_AMOUNT);
        vault.unlock();
        vm.stopPrank();

        uint256 slashAmount = 400 ether;
        vm.prank(adjudicator);
        vault.slash(alice, slashAmount);

        assertEq(vault.balanceOf(alice), LOCK_AMOUNT - slashAmount);
        assertEq(uint256(vault.lockStateOf(alice)), uint256(ILock.LockState.Unlocking));
    }

    function test_slash_unlocking_fullSlash_resetsToIdle() public {
        vm.startPrank(alice);
        vault.lock(LOCK_AMOUNT);
        vault.unlock();
        vm.stopPrank();

        vm.prank(adjudicator);
        vault.slash(alice, LOCK_AMOUNT);

        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.unlockTimestampOf(alice), 0);
        assertEq(uint256(vault.lockStateOf(alice)), uint256(ILock.LockState.Idle));
    }

    function test_slash_unlocking_partialSlash_canStillWithdraw() public {
        vm.startPrank(alice);
        vault.lock(LOCK_AMOUNT);
        vault.unlock();
        vm.stopPrank();

        uint256 slashAmount = 200 ether;
        vm.prank(adjudicator);
        vault.slash(alice, slashAmount);

        vm.warp(block.timestamp + 14 days);

        uint256 aliceBalBefore = token.balanceOf(alice);
        vm.prank(alice);
        vault.withdraw();

        assertEq(token.balanceOf(alice), aliceBalBefore + LOCK_AMOUNT - slashAmount);
    }

    // -------------------------------------------------------------------------
    // Slash — edge cases
    // -------------------------------------------------------------------------

    function test_slash_multipleSlashes() public {
        vm.prank(alice);
        vault.lock(LOCK_AMOUNT);

        vm.startPrank(adjudicator);
        vault.slash(alice, 100 ether);
        vault.slash(alice, 200 ether);
        vm.stopPrank();

        assertEq(vault.balanceOf(alice), LOCK_AMOUNT - 300 ether);
    }

    function test_slash_independentPerUser() public {
        vm.prank(alice);
        vault.lock(LOCK_AMOUNT);
        vm.prank(bob);
        vault.lock(LOCK_AMOUNT);

        vm.prank(adjudicator);
        vault.slash(alice, 500 ether);

        assertEq(vault.balanceOf(alice), LOCK_AMOUNT - 500 ether);
        assertEq(vault.balanceOf(bob), LOCK_AMOUNT);
    }

    function test_slash_fullSlash_thenCanLockAgain() public {
        vm.prank(alice);
        vault.lock(LOCK_AMOUNT);

        vm.prank(adjudicator);
        vault.slash(alice, LOCK_AMOUNT);

        // Alice can lock again after being fully slashed
        vm.prank(alice);
        vault.lock(500 ether);

        assertEq(vault.balanceOf(alice), 500 ether);
        assertEq(uint256(vault.lockStateOf(alice)), uint256(ILock.LockState.Locked));
    }
}
