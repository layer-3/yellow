// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ILock} from "../src/interfaces/ILock.sol";
import {ISlash} from "../src/interfaces/ISlash.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {AppRegistry} from "../src/AppRegistry.sol";
import {YellowToken} from "../src/Token.sol";
import {LockerTestBase} from "./Locker.t.sol";

/// @dev Runs all shared ILock tests against AppRegistry.
contract AppRegistryLockerTest is LockerTestBase {
    AppRegistry vault;

    function setUp() public override {
        token = new YellowToken(treasury);
        vault = new AppRegistry(address(token), UNLOCK_PERIOD, treasury);
        super.setUp();
    }

    function _vault() internal view override returns (ILock) {
        return ILock(address(vault));
    }

    function _vaultAddress() internal view override returns (address) {
        return address(vault);
    }
}

// -------------------------------------------------------------------------
// AppRegistry-specific: constructor
// -------------------------------------------------------------------------
contract AppRegistryConstructorTest is Test {
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
// Slash tests (AppRegistry-specific)
// -------------------------------------------------------------------------
contract AppRegistrySlashTest is Test {
    AppRegistry vault;
    YellowToken token;

    address treasury = makeAddr("treasury");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address owner = makeAddr("owner");
    address adjudicator = makeAddr("adjudicator");

    uint256 constant LOCK_AMOUNT = 1000 ether;
    bytes32 immutable ADJUDICATOR_ROLE = keccak256("ADJUDICATOR_ROLE");

    function setUp() public {
        token = new YellowToken(treasury);
        vault = new AppRegistry(address(token), 14 days, owner);
        vm.prank(owner);
        vault.grantRole(ADJUDICATOR_ROLE, adjudicator);

        vm.startPrank(treasury);
        require(token.transfer(alice, 10_000 ether));
        require(token.transfer(bob, 10_000 ether));
        vm.stopPrank();

        vm.prank(alice);
        token.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        token.approve(address(vault), type(uint256).max);
    }

    // -- access control --

    function test_slash_revert_ifNotAdjudicator() public {
        vm.prank(alice);
        vault.lock(alice, LOCK_AMOUNT);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, ADJUDICATOR_ROLE)
        );
        vault.slash(alice, 100 ether, treasury, "0xDecisionHash");
    }

    function test_slash_revert_ifRecipientIsAdjudicator() public {
        vm.prank(alice);
        vault.lock(alice, LOCK_AMOUNT);

        vm.prank(adjudicator);
        vm.expectRevert(abi.encodeWithSelector(ISlash.RecipientIsAdjudicator.selector));
        vault.slash(alice, 100 ether, adjudicator, "0xDecisionHash");
    }

    function test_slash_revert_ifUserHasNoBalance() public {
        vm.prank(adjudicator);
        vm.expectRevert(abi.encodeWithSelector(ISlash.InsufficientBalance.selector));
        vault.slash(alice, 100 ether, treasury, "0xDecisionHash");
    }

    function test_slash_revert_ifAmountExceedsBalance() public {
        vm.prank(alice);
        vault.lock(alice, LOCK_AMOUNT);

        vm.prank(adjudicator);
        vm.expectRevert(abi.encodeWithSelector(ISlash.InsufficientBalance.selector));
        vault.slash(alice, LOCK_AMOUNT + 1, treasury, "0xDecisionHash");
    }

    // -- while Locked --

    function test_slash_locked_partialSlash_reducesBalance() public {
        vm.prank(alice);
        vault.lock(alice, LOCK_AMOUNT);

        uint256 slashAmount = 300 ether;
        vm.prank(adjudicator);
        vault.slash(alice, slashAmount, treasury, "0xDecisionHash");

        assertEq(vault.balanceOf(alice), LOCK_AMOUNT - slashAmount);
        assertEq(uint256(vault.lockStateOf(alice)), uint256(ILock.LockState.Locked));
    }

    function test_slash_locked_partialSlash_transfersToRecipient() public {
        vm.prank(alice);
        vault.lock(alice, LOCK_AMOUNT);

        uint256 slashAmount = 300 ether;
        uint256 recipientBalBefore = token.balanceOf(treasury);

        vm.prank(adjudicator);
        vault.slash(alice, slashAmount, treasury, "0xDecisionHash");

        assertEq(token.balanceOf(treasury), recipientBalBefore + slashAmount);
    }

    function test_slash_locked_fullSlash_resetsToIdle() public {
        vm.prank(alice);
        vault.lock(alice, LOCK_AMOUNT);

        vm.prank(adjudicator);
        vault.slash(alice, LOCK_AMOUNT, treasury, "0xDecisionHash");

        assertEq(vault.balanceOf(alice), 0);
        assertEq(uint256(vault.lockStateOf(alice)), uint256(ILock.LockState.Idle));
    }

    function test_slash_locked_emitsSlashed() public {
        vm.prank(alice);
        vault.lock(alice, LOCK_AMOUNT);

        uint256 slashAmount = 500 ether;
        vm.prank(adjudicator);
        vm.expectEmit(true, true, false, true, address(vault));
        emit ISlash.Slashed(alice, slashAmount, treasury, "0xDecisionHash");
        vault.slash(alice, slashAmount, treasury, "0xDecisionHash");
    }

    // -- while Unlocking --

    function test_slash_unlocking_partialSlash_remainsUnlocking() public {
        vm.startPrank(alice);
        vault.lock(alice, LOCK_AMOUNT);
        vault.unlock();
        vm.stopPrank();

        uint256 slashAmount = 400 ether;
        vm.prank(adjudicator);
        vault.slash(alice, slashAmount, treasury, "0xDecisionHash");

        assertEq(vault.balanceOf(alice), LOCK_AMOUNT - slashAmount);
        assertEq(uint256(vault.lockStateOf(alice)), uint256(ILock.LockState.Unlocking));
    }

    function test_slash_unlocking_fullSlash_resetsToIdle() public {
        vm.startPrank(alice);
        vault.lock(alice, LOCK_AMOUNT);
        vault.unlock();
        vm.stopPrank();

        vm.prank(adjudicator);
        vault.slash(alice, LOCK_AMOUNT, treasury, "0xDecisionHash");

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
        vault.slash(alice, slashAmount, treasury, "0xDecisionHash");

        vm.warp(block.timestamp + 14 days);

        uint256 aliceBalBefore = token.balanceOf(alice);
        vm.prank(alice);
        vault.withdraw(alice);

        assertEq(token.balanceOf(alice), aliceBalBefore + LOCK_AMOUNT - slashAmount);
    }

    // -- edge cases --

    function test_slash_multipleSlashes() public {
        vm.prank(alice);
        vault.lock(alice, LOCK_AMOUNT);

        vm.startPrank(adjudicator);
        vault.slash(alice, 100 ether, treasury, "0xDecisionHash");
        vault.slash(alice, 200 ether, treasury, "0xDecisionHash");
        vm.stopPrank();

        assertEq(vault.balanceOf(alice), LOCK_AMOUNT - 300 ether);
    }

    function test_slash_independentPerUser() public {
        vm.prank(alice);
        vault.lock(alice, LOCK_AMOUNT);
        vm.prank(bob);
        vault.lock(bob, LOCK_AMOUNT);

        vm.prank(adjudicator);
        vault.slash(alice, 500 ether, treasury, "0xDecisionHash");

        assertEq(vault.balanceOf(alice), LOCK_AMOUNT - 500 ether);
        assertEq(vault.balanceOf(bob), LOCK_AMOUNT);
    }

    function test_slash_fullSlash_thenCanLockAgain() public {
        vm.prank(alice);
        vault.lock(alice, LOCK_AMOUNT);

        vm.prank(adjudicator);
        vault.slash(alice, LOCK_AMOUNT, treasury, "0xDecisionHash");

        vm.prank(alice);
        vault.lock(alice, 500 ether);

        assertEq(vault.balanceOf(alice), 500 ether);
        assertEq(uint256(vault.lockStateOf(alice)), uint256(ILock.LockState.Locked));
    }
}
