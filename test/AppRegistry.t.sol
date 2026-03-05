// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ILock} from "../src/interfaces/ILock.sol";
import {ISlash} from "../src/interfaces/ISlash.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {AppRegistry} from "../src/AppRegistry.sol";
import {YellowToken} from "../src/Token.sol";

contract AppRegistryTest_Base is Test {
    AppRegistry vault;
    YellowToken token;

    address treasury = makeAddr("treasury");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address owner = makeAddr("owner");
    address adjudicator = makeAddr("adjudicator");

    uint256 constant INITIAL_BALANCE = 10_000 ether;
    uint256 constant LOCK_AMOUNT = 1000 ether;
    uint256 constant UNLOCK_PERIOD = 14 days;
    bytes32 immutable ADJUDICATOR_ROLE = keccak256("ADJUDICATOR_ROLE");

    function setUp() public virtual {
        token = new YellowToken(treasury);
        vault = new AppRegistry(address(token), UNLOCK_PERIOD, owner);
        vm.prank(owner);
        vault.grantRole(ADJUDICATOR_ROLE, adjudicator);

        // Fund alice and bob
        vm.startPrank(treasury);
        require(token.transfer(alice, INITIAL_BALANCE));
        require(token.transfer(bob, INITIAL_BALANCE));
        vm.stopPrank();

        // Approve vault for alice and bob
        vm.prank(alice);
        token.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        token.approve(address(vault), type(uint256).max);
    }
}

// -------------------------------------------------------------------------
// Constructor
// -------------------------------------------------------------------------
contract AppRegistryTest_constructor is AppRegistryTest_Base {
    function test_revert_ifAssetIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(ILock.InvalidAddress.selector));
        new AppRegistry(address(0), UNLOCK_PERIOD, owner);
    }

    function test_revert_ifUnlockPeriodIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(ILock.InvalidAmount.selector));
        new AppRegistry(address(token), 0, owner);
    }

    function test_setsAsset() public view {
        assertEq(vault.asset(), address(token));
    }

    function test_setsUnlockPeriod() public view {
        assertEq(vault.UNLOCK_PERIOD(), UNLOCK_PERIOD);
    }
}

// -------------------------------------------------------------------------
// Initial state
// -------------------------------------------------------------------------
contract AppRegistryTest_initialState is AppRegistryTest_Base {
    function test_idle() public view {
        assertEq(uint256(vault.lockStateOf(alice)), uint256(ILock.LockState.Idle));
    }

    function test_zeroBalance() public view {
        assertEq(vault.balanceOf(alice), 0);
    }

    function test_zeroUnlockTimestamp() public view {
        assertEq(vault.unlockTimestampOf(alice), 0);
    }
}

// -------------------------------------------------------------------------
// lock()
// -------------------------------------------------------------------------
contract AppRegistryTest_lock is AppRegistryTest_Base {
    function test_lock_success() public {
        vm.prank(alice);
        vault.lock(alice, LOCK_AMOUNT);

        assertEq(token.balanceOf(alice), INITIAL_BALANCE - LOCK_AMOUNT);
        assertEq(token.balanceOf(address(vault)), LOCK_AMOUNT);

        assertEq(vault.balanceOf(alice), LOCK_AMOUNT);
        assertEq(uint8(vault.lockStateOf(alice)), uint8(ILock.LockState.Locked));
    }

    function test_lock_emitsEvent_Locked() public {
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

    function test_lock_creditsTarget() public {
        vm.prank(alice);
        vault.lock(bob, LOCK_AMOUNT);

        assertEq(vault.balanceOf(bob), LOCK_AMOUNT);
        assertEq(vault.balanceOf(alice), 0);
    }

    function test_lock_debitsPayerNotTarget() public {
        vm.prank(alice);
        vault.lock(bob, LOCK_AMOUNT);

        assertEq(token.balanceOf(alice), INITIAL_BALANCE - LOCK_AMOUNT);
        assertEq(token.balanceOf(bob), INITIAL_BALANCE);
    }

    function test_lock_revert_ifTargetAlreadyUnlocking() public {
        vm.startPrank(alice);
        vault.lock(alice, LOCK_AMOUNT);
        vault.unlock();
        vm.stopPrank();

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(ILock.AlreadyUnlocking.selector));
        vault.lock(alice, LOCK_AMOUNT);
    }
}

// -------------------------------------------------------------------------
// unlock()
// -------------------------------------------------------------------------
contract AppRegistryTest_unlock is AppRegistryTest_Base {
    function setUp() public override {
        super.setUp();
        vm.prank(alice);
        vault.lock(alice, LOCK_AMOUNT);
    }

    function test_unlock_success() public {
        vm.prank(alice);
        vault.unlock();

        assertEq(vault.unlockTimestampOf(alice), block.timestamp + UNLOCK_PERIOD);
        assertEq(uint8(vault.lockStateOf(alice)), uint8(ILock.LockState.Unlocking));
    }

    function test_unlock_emitsEvent_UnlockInitiated() public {
        vm.prank(alice);
        uint256 expectedAvailableAt = block.timestamp + UNLOCK_PERIOD;
        vm.expectEmit(true, false, false, true, address(vault));
        emit ILock.UnlockInitiated(alice, LOCK_AMOUNT, expectedAvailableAt);
        vault.unlock();
    }

    function test_unlock_revert_ifZeroLocked() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(ILock.NotLocked.selector));
        vault.unlock();
    }

    function test_unlock_revert_ifAlreadyUnlocking() public {
        vm.startPrank(alice);
        vault.unlock();

        vm.expectRevert(abi.encodeWithSelector(ILock.AlreadyUnlocking.selector));
        vault.unlock();
        vm.stopPrank();
    }
}

// -------------------------------------------------------------------------
// relock()
// -------------------------------------------------------------------------
contract AppRegistryTest_relock is AppRegistryTest_Base {
    function setUp() public override {
        super.setUp();
        vm.startPrank(alice);
        vault.lock(alice, LOCK_AMOUNT);
        vault.unlock();
        vm.stopPrank();
    }

    function test_relock_success() public {
        vm.prank(alice);
        vault.relock();

        assertEq(uint8(vault.lockStateOf(alice)), uint8(ILock.LockState.Locked));
        assertEq(vault.unlockTimestampOf(alice), 0);
    }

    function test_relock_emitsRelocked() public {
        vm.prank(alice);
        vm.expectEmit(true, false, false, true, address(vault));
        emit ILock.Relocked(alice, LOCK_AMOUNT);
        vault.relock();
    }

    function test_relock_revert_ifNotUnlocking() public {
        vm.startPrank(bob);
        vault.lock(bob, LOCK_AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(ILock.NotUnlocking.selector));
        vault.relock();
        vm.stopPrank();
    }
}

// -------------------------------------------------------------------------
// withdraw()
// -------------------------------------------------------------------------
contract AppRegistryTest_withdraw is AppRegistryTest_Base {
    function setUp() public override {
        super.setUp();
        vm.startPrank(alice);
        vault.lock(alice, LOCK_AMOUNT);
        vault.unlock();
        vm.stopPrank();
    }

    function test_withdraw_success() public {
        vm.warp(block.timestamp + UNLOCK_PERIOD);

        uint256 balBefore = token.balanceOf(alice);
        vm.prank(alice);
        vault.withdraw(alice);

        assertEq(token.balanceOf(alice), balBefore + LOCK_AMOUNT);
        assertEq(uint8(vault.lockStateOf(alice)), uint8(ILock.LockState.Idle));
    }

    function test_withdraw_emitsEvent_Withdrawn() public {
        vm.warp(block.timestamp + UNLOCK_PERIOD);

        vm.prank(alice);
        vm.expectEmit(true, false, false, true, address(vault));
        emit ILock.Withdrawn(alice, LOCK_AMOUNT);
        vault.withdraw(alice);
    }

    function test_withdraw_revert_ifNotUnlocking() public {
        vm.startPrank(bob);
        vault.lock(bob, LOCK_AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(ILock.NotUnlocking.selector));
        vault.withdraw(bob);
        vm.stopPrank();
    }

    function test_withdraw_revert_ifPeriodNotElapsed() public {
        uint256 availableAt = vault.unlockTimestampOf(alice);
        vm.warp(availableAt - 1);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ILock.UnlockPeriodNotElapsed.selector, availableAt));
        vault.withdraw(alice);
    }

    function test_withdraw_sendsToDestination() public {
        vm.warp(block.timestamp + UNLOCK_PERIOD);

        uint256 bobBalBefore = token.balanceOf(bob);
        vm.prank(alice);
        vault.withdraw(bob);

        assertEq(token.balanceOf(bob), bobBalBefore + LOCK_AMOUNT);
        assertEq(vault.balanceOf(alice), 0);
    }
}

// -------------------------------------------------------------------------
// Full lifecycle
// -------------------------------------------------------------------------
contract AppRegistryTest_fullCycle is AppRegistryTest_Base {
    function test_fullCycle_lockUnlockWithdraw() public {
        uint256 aliceBalBefore = token.balanceOf(alice);

        vm.prank(alice);
        vault.lock(alice, LOCK_AMOUNT);
        assertEq(uint256(vault.lockStateOf(alice)), uint256(ILock.LockState.Locked));

        vm.prank(alice);
        vault.unlock();
        assertEq(uint8(vault.lockStateOf(alice)), uint8(ILock.LockState.Unlocking));

        vm.warp(block.timestamp + UNLOCK_PERIOD);
        vm.prank(alice);
        vault.withdraw(alice);
        assertEq(uint256(vault.lockStateOf(alice)), uint256(ILock.LockState.Idle));

        assertEq(token.balanceOf(alice), aliceBalBefore);
    }
}

// -------------------------------------------------------------------------
// Slash — access control
// -------------------------------------------------------------------------
contract AppRegistryTest_slash is AppRegistryTest_Base {
    function test_slash_revert_ifNotAdjudicator() public {
        vm.prank(alice);
        vault.lock(alice, LOCK_AMOUNT);

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
        vault.lock(alice, LOCK_AMOUNT);

        vm.prank(adjudicator);
        vm.expectRevert(abi.encodeWithSelector(ISlash.InsufficientBalance.selector));
        vault.slash(alice, LOCK_AMOUNT + 1);
    }

    // -------------------------------------------------------------------------
    // Slash — while Locked
    // -------------------------------------------------------------------------

    function test_slash_locked_partialSlash_reducesBalance() public {
        vm.prank(alice);
        vault.lock(alice, LOCK_AMOUNT);

        uint256 slashAmount = 300 ether;
        vm.prank(adjudicator);
        vault.slash(alice, slashAmount);

        assertEq(vault.balanceOf(alice), LOCK_AMOUNT - slashAmount);
        assertEq(uint256(vault.lockStateOf(alice)), uint256(ILock.LockState.Locked));
    }

    function test_slash_locked_partialSlash_transfersToCaller() public {
        vm.prank(alice);
        vault.lock(alice, LOCK_AMOUNT);

        uint256 slashAmount = 300 ether;
        uint256 adjBalBefore = token.balanceOf(adjudicator);

        vm.prank(adjudicator);
        vault.slash(alice, slashAmount);

        assertEq(token.balanceOf(adjudicator), adjBalBefore + slashAmount);
    }

    function test_slash_locked_fullSlash_resetsToIdle() public {
        vm.prank(alice);
        vault.lock(alice, LOCK_AMOUNT);

        vm.prank(adjudicator);
        vault.slash(alice, LOCK_AMOUNT);

        assertEq(vault.balanceOf(alice), 0);
        assertEq(uint256(vault.lockStateOf(alice)), uint256(ILock.LockState.Idle));
    }

    function test_slash_locked_emitsSlashed() public {
        vm.prank(alice);
        vault.lock(alice, LOCK_AMOUNT);

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
        vault.lock(alice, LOCK_AMOUNT);
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
        vault.lock(alice, LOCK_AMOUNT);
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
        vault.lock(alice, LOCK_AMOUNT);
        vault.unlock();
        vm.stopPrank();

        uint256 slashAmount = 200 ether;
        vm.prank(adjudicator);
        vault.slash(alice, slashAmount);

        vm.warp(block.timestamp + 14 days);

        uint256 aliceBalBefore = token.balanceOf(alice);
        vm.prank(alice);
        vault.withdraw(alice);

        assertEq(token.balanceOf(alice), aliceBalBefore + LOCK_AMOUNT - slashAmount);
    }

    // -------------------------------------------------------------------------
    // Slash — edge cases
    // -------------------------------------------------------------------------

    function test_slash_multipleSlashes() public {
        vm.prank(alice);
        vault.lock(alice, LOCK_AMOUNT);

        vm.startPrank(adjudicator);
        vault.slash(alice, 100 ether);
        vault.slash(alice, 200 ether);
        vm.stopPrank();

        assertEq(vault.balanceOf(alice), LOCK_AMOUNT - 300 ether);
    }

    function test_slash_independentPerUser() public {
        vm.prank(alice);
        vault.lock(alice, LOCK_AMOUNT);
        vm.prank(bob);
        vault.lock(bob, LOCK_AMOUNT);

        vm.prank(adjudicator);
        vault.slash(alice, 500 ether);

        assertEq(vault.balanceOf(alice), LOCK_AMOUNT - 500 ether);
        assertEq(vault.balanceOf(bob), LOCK_AMOUNT);
    }

    function test_slash_fullSlash_thenCanLockAgain() public {
        vm.prank(alice);
        vault.lock(alice, LOCK_AMOUNT);

        vm.prank(adjudicator);
        vault.slash(alice, LOCK_AMOUNT);

        // Alice can lock again after being fully slashed
        vm.prank(alice);
        vault.lock(alice, 500 ether);

        assertEq(vault.balanceOf(alice), 500 ether);
        assertEq(uint256(vault.lockStateOf(alice)), uint256(ILock.LockState.Locked));
    }
}
