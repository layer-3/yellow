// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {LockerTestBase} from "./Locker.t.sol";

import {ILock} from "../src/interfaces/ILock.sol";
import {ISlash} from "../src/interfaces/ISlash.sol";
import {AppRegistry} from "../src/AppRegistry.sol";
import {YellowToken} from "../src/Token.sol";

/// @dev Runs all shared ILock tests against AppRegistry.
contract AppRegistryTest_Locker is LockerTestBase {
    AppRegistry appRegistry;

    function setUp() public override {
        token = new YellowToken(treasury);
        appRegistry = new AppRegistry(address(token), UNLOCK_PERIOD, treasury);
        super.setUp();
    }

    function _vault() internal view override returns (ILock) {
        return ILock(address(appRegistry));
    }

    function _vaultAddress() internal view override returns (address) {
        return address(appRegistry);
    }
}

// -------------------------------------------------------------------------
// AppRegistry-specific: constructor
// -------------------------------------------------------------------------
contract AppRegistryTest_constructor is Test {
    function test_revert_ifAssetIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(ILock.InvalidAddress.selector));
        new AppRegistry(address(0), 14 days, address(this));
    }

    function test_revert_ifUnlockPeriodIsZero() public {
        YellowToken t = new YellowToken(address(this));
        vm.expectRevert(abi.encodeWithSelector(ILock.InvalidPeriod.selector));
        new AppRegistry(address(t), 0, address(this));
    }

    function test_revert_ifAdminIsZero() public {
        YellowToken t = new YellowToken(address(this));
        vm.expectRevert(abi.encodeWithSelector(ILock.InvalidAddress.selector));
        new AppRegistry(address(t), 14 days, address(0));
    }

    function test_setsAssetAndPeriod() public {
        YellowToken t = new YellowToken(address(this));
        AppRegistry v = new AppRegistry(address(t), 14 days, address(this));
        assertEq(v.asset(), address(t));
        assertEq(v.ASSET(), address(t));
        assertEq(v.UNLOCK_PERIOD(), 14 days);
    }
}

// -------------------------------------------------------------------------
// Slash tests (AppRegistry-specific) — shared base
// -------------------------------------------------------------------------
contract AppRegistryTest_slash_base is Test {
    AppRegistry appRegistry;
    YellowToken token;

    address treasury = makeAddr("treasury");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address owner = makeAddr("owner");
    address adjudicator = makeAddr("adjudicator");

    uint256 constant LOCK_AMOUNT = 1000 ether;
    bytes32 immutable ADJUDICATOR_ROLE = keccak256("ADJUDICATOR_ROLE");

    function setUp() public virtual {
        token = new YellowToken(treasury);
        appRegistry = new AppRegistry(address(token), 14 days, owner);
        vm.prank(owner);
        appRegistry.grantRole(ADJUDICATOR_ROLE, adjudicator);

        vm.startPrank(treasury);
        require(token.transfer(alice, 10_000 ether));
        require(token.transfer(bob, 10_000 ether));
        vm.stopPrank();

        vm.prank(alice);
        token.approve(address(appRegistry), type(uint256).max);
        vm.prank(bob);
        token.approve(address(appRegistry), type(uint256).max);
    }
}

// -------------------------------------------------------------------------
// Slash — access control
// -------------------------------------------------------------------------
contract AppRegistryTest_slash_accessControl is AppRegistryTest_slash_base {
    function setUp() public override {
        super.setUp();
        vm.prank(alice);
        appRegistry.lock(alice, LOCK_AMOUNT);
    }

    function test_slash_revert_ifNotAdjudicator() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, ADJUDICATOR_ROLE)
        );
        appRegistry.slash(alice, 100 ether, treasury, "0xDecisionHash");
    }

    function test_slash_revert_ifRecipientIsAdjudicator() public {
        vm.prank(adjudicator);
        vm.expectRevert(abi.encodeWithSelector(ISlash.RecipientIsAdjudicator.selector));
        appRegistry.slash(alice, 100 ether, adjudicator, "0xDecisionHash");
    }

    function test_slash_revert_ifUserHasNoBalance() public {
        vm.prank(adjudicator);
        vm.expectRevert(abi.encodeWithSelector(ISlash.InsufficientBalance.selector));
        appRegistry.slash(bob, 100 ether, treasury, "0xDecisionHash");
    }

    function test_slash_revert_ifAmountExceedsBalance() public {
        vm.prank(adjudicator);
        vm.expectRevert(abi.encodeWithSelector(ISlash.InsufficientBalance.selector));
        appRegistry.slash(alice, LOCK_AMOUNT + 1, treasury, "0xDecisionHash");
    }

    // -------------------------------------------------------------------------
    // Slash — while Locked
    // -------------------------------------------------------------------------

    function test_slash_locked_partialSlash_reducesBalance() public {
        uint256 slashAmount = 300 ether;
        vm.prank(adjudicator);
        appRegistry.slash(alice, slashAmount, treasury, "0xDecisionHash");

        assertEq(appRegistry.balanceOf(alice), LOCK_AMOUNT - slashAmount);
        assertEq(uint256(appRegistry.lockStateOf(alice)), uint256(ILock.LockState.Locked));
    }

    function test_slash_locked_partialSlash_transfersToRecipient() public {
        uint256 slashAmount = 300 ether;
        uint256 recipientBalBefore = token.balanceOf(treasury);

        vm.prank(adjudicator);
        appRegistry.slash(alice, slashAmount, treasury, "0xDecisionHash");

        assertEq(token.balanceOf(treasury), recipientBalBefore + slashAmount);
    }

    function test_slash_locked_fullSlash_resetsToIdle() public {
        vm.prank(adjudicator);
        appRegistry.slash(alice, LOCK_AMOUNT, treasury, "0xDecisionHash");

        assertEq(appRegistry.balanceOf(alice), 0);
        assertEq(uint256(appRegistry.lockStateOf(alice)), uint256(ILock.LockState.Idle));
    }

    function test_slash_locked_emitsSlashed() public {
        uint256 slashAmount = 500 ether;
        vm.prank(adjudicator);
        vm.expectEmit(true, true, false, true, address(appRegistry));
        emit ISlash.Slashed(alice, slashAmount, treasury, "0xDecisionHash");
        appRegistry.slash(alice, slashAmount, treasury, "0xDecisionHash");
    }
}

// -------------------------------------------------------------------------
// Slash — while Unlocking
// -------------------------------------------------------------------------
contract AppRegistrySlashTest_unlocking is AppRegistryTest_slash_base {
    function setUp() public override {
        super.setUp();
        vm.startPrank(alice);
        appRegistry.lock(alice, LOCK_AMOUNT);
        appRegistry.unlock();
        vm.stopPrank();
    }

    function test_slash_unlocking_partialSlash_remainsUnlocking() public {
        uint256 slashAmount = 400 ether;
        vm.prank(adjudicator);
        appRegistry.slash(alice, slashAmount, treasury, "0xDecisionHash");

        assertEq(appRegistry.balanceOf(alice), LOCK_AMOUNT - slashAmount);
        assertEq(uint256(appRegistry.lockStateOf(alice)), uint256(ILock.LockState.Unlocking));
    }

    function test_slash_unlocking_fullSlash_resetsToIdle() public {
        vm.prank(adjudicator);
        appRegistry.slash(alice, LOCK_AMOUNT, treasury, "0xDecisionHash");

        assertEq(appRegistry.balanceOf(alice), 0);
        assertEq(appRegistry.unlockTimestampOf(alice), 0);
        assertEq(uint256(appRegistry.lockStateOf(alice)), uint256(ILock.LockState.Idle));
    }

    function test_slash_unlocking_partialSlash_canStillWithdraw() public {
        uint256 slashAmount = 200 ether;
        vm.prank(adjudicator);
        appRegistry.slash(alice, slashAmount, treasury, "0xDecisionHash");

        vm.warp(block.timestamp + 14 days);

        uint256 aliceBalBefore = token.balanceOf(alice);
        vm.prank(alice);
        appRegistry.withdraw(alice);

        assertEq(token.balanceOf(alice), aliceBalBefore + LOCK_AMOUNT - slashAmount);
    }
}

// -------------------------------------------------------------------------
// Slash — edge cases
// -------------------------------------------------------------------------
contract AppRegistryTest_slash_edgeCases is AppRegistryTest_slash_base {
    function test_slash_multipleSlashes() public {
        vm.prank(alice);
        appRegistry.lock(alice, LOCK_AMOUNT);

        vm.startPrank(adjudicator);
        appRegistry.slash(alice, 100 ether, treasury, "0xDecisionHash");
        appRegistry.slash(alice, 200 ether, treasury, "0xDecisionHash");
        vm.stopPrank();

        assertEq(appRegistry.balanceOf(alice), LOCK_AMOUNT - 300 ether);
    }

    function test_slash_independentPerUser() public {
        vm.prank(alice);
        appRegistry.lock(alice, LOCK_AMOUNT);
        vm.prank(bob);
        appRegistry.lock(bob, LOCK_AMOUNT);

        vm.prank(adjudicator);
        appRegistry.slash(alice, 500 ether, treasury, "0xDecisionHash");

        assertEq(appRegistry.balanceOf(alice), LOCK_AMOUNT - 500 ether);
        assertEq(appRegistry.balanceOf(bob), LOCK_AMOUNT);
    }

    function test_slash_fullSlash_thenCanLockAgain() public {
        vm.prank(alice);
        appRegistry.lock(alice, LOCK_AMOUNT);

        vm.prank(adjudicator);
        appRegistry.slash(alice, LOCK_AMOUNT, treasury, "0xDecisionHash");

        vm.prank(alice);
        appRegistry.lock(alice, 500 ether);

        assertEq(appRegistry.balanceOf(alice), 500 ether);
        assertEq(uint256(appRegistry.lockStateOf(alice)), uint256(ILock.LockState.Locked));
    }
}

// -------------------------------------------------------------------------
// Slash cooldown
// -------------------------------------------------------------------------
contract AppRegistryTest_slashCooldown is AppRegistryTest_slash_base {
    uint256 constant COOLDOWN = 1 hours;

    function setUp() public override {
        super.setUp();

        vm.prank(owner);
        appRegistry.setSlashCooldown(COOLDOWN);

        vm.prank(alice);
        appRegistry.lock(alice, LOCK_AMOUNT);
        vm.prank(bob);
        appRegistry.lock(bob, LOCK_AMOUNT);
    }

    function test_setSlashCooldown_onlyAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        appRegistry.setSlashCooldown(2 hours);
    }

    function test_setSlashCooldown_emitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(false, false, false, true, address(appRegistry));
        emit AppRegistry.SlashCooldownUpdated(COOLDOWN, 2 hours);
        appRegistry.setSlashCooldown(2 hours);

        assertEq(appRegistry.slashCooldown(), 2 hours);
    }

    function test_slash_revert_ifCooldownActive() public {
        vm.prank(adjudicator);
        appRegistry.slash(alice, 100 ether, treasury, "first");

        vm.prank(adjudicator);
        vm.expectRevert(
            abi.encodeWithSelector(
                AppRegistry.SlashCooldownActive.selector, block.timestamp + COOLDOWN
            )
        );
        appRegistry.slash(bob, 100 ether, treasury, "second");
    }

    function test_slash_succeedsAfterCooldown() public {
        vm.prank(adjudicator);
        appRegistry.slash(alice, 100 ether, treasury, "first");

        vm.warp(block.timestamp + COOLDOWN);

        vm.prank(adjudicator);
        appRegistry.slash(bob, 100 ether, treasury, "second");

        assertEq(appRegistry.balanceOf(alice), LOCK_AMOUNT - 100 ether);
        assertEq(appRegistry.balanceOf(bob), LOCK_AMOUNT - 100 ether);
    }

    function test_slash_batchingBlockedWithCooldown() public {
        // Adjudicator cannot slash two users in the same block
        vm.startPrank(adjudicator);
        appRegistry.slash(alice, 100 ether, treasury, "first");

        vm.expectRevert();
        appRegistry.slash(bob, 100 ether, treasury, "second");
        vm.stopPrank();
    }

    function test_slash_noCooldown_batchingAllowed() public {
        // Disable cooldown
        vm.prank(owner);
        appRegistry.setSlashCooldown(0);

        vm.startPrank(adjudicator);
        appRegistry.slash(alice, 100 ether, treasury, "first");
        appRegistry.slash(bob, 100 ether, treasury, "second");
        vm.stopPrank();

        assertEq(appRegistry.balanceOf(alice), LOCK_AMOUNT - 100 ether);
        assertEq(appRegistry.balanceOf(bob), LOCK_AMOUNT - 100 ether);
    }
}
