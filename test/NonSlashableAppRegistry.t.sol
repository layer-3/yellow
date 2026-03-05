// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ILock2} from "../src/interfaces/ILock2.sol";
import {NonSlashableAppRegistry} from "../src/NonSlashableAppRegistry.sol";
import {YellowToken} from "../src/Token.sol";

contract NonSlashableAppRegistryTest_Base is Test {
    NonSlashableAppRegistry vault;
    YellowToken token;

    address treasury = makeAddr("treasury");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint256 constant INITIAL_BALANCE = 10_000 ether;
    uint256 constant LOCK_AMOUNT = 1000 ether;
    uint256 constant UNLOCK_PERIOD = 14 days;

    function setUp() public virtual {
        token = new YellowToken(treasury);
        vault = new NonSlashableAppRegistry(address(token), UNLOCK_PERIOD);

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
contract NonSlashableAppRegistryTest_constructor is NonSlashableAppRegistryTest_Base {
    function test_revert_ifAssetIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(ILock2.InvalidAddress.selector));
        new NonSlashableAppRegistry(address(0), UNLOCK_PERIOD);
    }

    function test_revert_ifUnlockPeriodIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(ILock2.InvalidAmount.selector));
        new NonSlashableAppRegistry(address(token), 0);
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
contract NonSlashableAppRegistryTest_initialState is NonSlashableAppRegistryTest_Base {
    function test_idle() public view {
        assertEq(uint256(vault.lockStateOf(alice)), uint256(ILock2.LockState.Idle));
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
contract NonSlashableAppRegistryTest_lock is NonSlashableAppRegistryTest_Base {
    function test_lock_success() public {
        vm.prank(alice);
        vault.lock(alice, LOCK_AMOUNT);

        assertEq(token.balanceOf(alice), INITIAL_BALANCE - LOCK_AMOUNT);
        assertEq(token.balanceOf(address(vault)), LOCK_AMOUNT);

        assertEq(vault.balanceOf(alice), LOCK_AMOUNT);
        assertEq(uint8(vault.lockStateOf(alice)), uint8(ILock2.LockState.Locked));
    }

    function test_lock_emitsEvent_Locked() public {
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
        vm.expectRevert(abi.encodeWithSelector(ILock2.AlreadyUnlocking.selector));
        vault.lock(alice, LOCK_AMOUNT);
    }
}

// -------------------------------------------------------------------------
// unlock()
// -------------------------------------------------------------------------
contract NonSlashableAppRegistryTest_unlock is NonSlashableAppRegistryTest_Base {
    function setUp() public override {
        super.setUp();
        vm.prank(alice);
        vault.lock(alice, LOCK_AMOUNT);
    }

    function test_unlock_success() public {
        vm.prank(alice);
        vault.unlock();

        assertEq(vault.unlockTimestampOf(alice), block.timestamp + UNLOCK_PERIOD);
        assertEq(uint8(vault.lockStateOf(alice)), uint8(ILock2.LockState.Unlocking));
    }

    function test_unlock_emitsEvent_UnlockInitiated() public {
        vm.prank(alice);
        uint256 expectedAvailableAt = block.timestamp + UNLOCK_PERIOD;
        vm.expectEmit(true, false, false, true, address(vault));
        emit ILock2.UnlockInitiated(alice, LOCK_AMOUNT, expectedAvailableAt);
        vault.unlock();
    }

    function test_unlock_revert_ifZeroLocked() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(ILock2.NotLocked.selector));
        vault.unlock();
    }

    function test_unlock_revert_ifAlreadyUnlocking() public {
        vm.startPrank(alice);
        vault.unlock();

        vm.expectRevert(abi.encodeWithSelector(ILock2.AlreadyUnlocking.selector));
        vault.unlock();
        vm.stopPrank();
    }
}

// -------------------------------------------------------------------------
// relock()
// -------------------------------------------------------------------------
contract NonSlashableAppRegistryTest_relock is NonSlashableAppRegistryTest_Base {
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

        assertEq(uint8(vault.lockStateOf(alice)), uint8(ILock2.LockState.Locked));
        assertEq(vault.unlockTimestampOf(alice), 0);
    }

    function test_relock_emitsRelocked() public {
        vm.prank(alice);
        vm.expectEmit(true, false, false, true, address(vault));
        emit ILock2.Relocked(alice, LOCK_AMOUNT);
        vault.relock();
    }

    function test_relock_revert_ifNotUnlocking() public {
        vm.startPrank(bob);
        vault.lock(bob, LOCK_AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(ILock2.NotUnlocking.selector));
        vault.relock();
        vm.stopPrank();
    }
}

// -------------------------------------------------------------------------
// withdraw()
// -------------------------------------------------------------------------
contract NonSlashableAppRegistryTest_withdraw is NonSlashableAppRegistryTest_Base {
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
        assertEq(uint8(vault.lockStateOf(alice)), uint8(ILock2.LockState.Idle));
    }

    function test_withdraw_emitsEvent_Withdrawn() public {
        vm.warp(block.timestamp + UNLOCK_PERIOD);

        vm.prank(alice);
        vm.expectEmit(true, false, false, true, address(vault));
        emit ILock2.Withdrawn(alice, LOCK_AMOUNT);
        vault.withdraw(alice);
    }

    function test_withdraw_revert_ifNotUnlocking() public {
        vm.startPrank(bob);
        vault.lock(bob, LOCK_AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(ILock2.NotUnlocking.selector));
        vault.withdraw(bob);
        vm.stopPrank();
    }

    function test_withdraw_revert_ifPeriodNotElapsed() public {
        uint256 availableAt = vault.unlockTimestampOf(alice);
        vm.warp(availableAt - 1);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ILock2.UnlockPeriodNotElapsed.selector, availableAt));
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
contract NonSlashableAppRegistryTest_fullCycle is NonSlashableAppRegistryTest_Base {
    function test_fullCycle_lockUnlockWithdraw() public {
        uint256 aliceBalBefore = token.balanceOf(alice);

        vm.prank(alice);
        vault.lock(alice, LOCK_AMOUNT);
        assertEq(uint256(vault.lockStateOf(alice)), uint256(ILock2.LockState.Locked));

        vm.prank(alice);
        vault.unlock();
        assertEq(uint8(vault.lockStateOf(alice)), uint8(ILock2.LockState.Unlocking));

        vm.warp(block.timestamp + UNLOCK_PERIOD);
        vm.prank(alice);
        vault.withdraw(alice);
        assertEq(uint256(vault.lockStateOf(alice)), uint256(ILock2.LockState.Idle));

        assertEq(token.balanceOf(alice), aliceBalBefore);
    }
}
