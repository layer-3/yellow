// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {YellowToken} from "../src/Token.sol";
import {Faucet} from "../src/Faucet.sol";

contract FaucetTest is Test {
    YellowToken token;
    Faucet faucet;

    address owner = address(this);
    address user1 = address(0xA);
    address user2 = address(0xB);

    uint256 constant DRIP_AMOUNT = 1_000 ether;
    uint256 constant COOLDOWN = 1 days;
    uint256 constant FAUCET_SUPPLY = 1_000_000 ether;

    function setUp() public {
        token = new YellowToken(address(this));
        faucet = new Faucet(IERC20(address(token)), DRIP_AMOUNT, COOLDOWN);
        require(token.transfer(address(faucet), FAUCET_SUPPLY));
    }

    // ── Constructor ─────────────────────────────────────────────────

    function test_constructor_setsState() public view {
        assertEq(address(faucet.TOKEN()), address(token));
        assertEq(faucet.owner(), owner);
        assertEq(faucet.dripAmount(), DRIP_AMOUNT);
        assertEq(faucet.cooldown(), COOLDOWN);
    }

    // ── drip ────────────────────────────────────────────────────────

    function test_drip_transfersTokens() public {
        vm.prank(user1);
        faucet.drip();
        assertEq(token.balanceOf(user1), DRIP_AMOUNT);
    }

    function test_drip_emitsDripped() public {
        vm.expectEmit(true, false, false, true);
        emit Faucet.Dripped(user1, DRIP_AMOUNT);
        vm.prank(user1);
        faucet.drip();
    }

    function test_drip_setsLastDrip() public {
        vm.prank(user1);
        faucet.drip();
        assertEq(faucet.lastDrip(user1), block.timestamp);
    }

    function test_drip_revert_ifCooldownActive() public {
        vm.prank(user1);
        faucet.drip();

        vm.prank(user1);
        vm.expectRevert("Faucet: cooldown active");
        faucet.drip();
    }

    function test_drip_worksAfterCooldown() public {
        vm.prank(user1);
        faucet.drip();

        vm.warp(block.timestamp + COOLDOWN);

        vm.prank(user1);
        faucet.drip();
        assertEq(token.balanceOf(user1), DRIP_AMOUNT * 2);
    }

    function test_drip_revert_ifInsufficientBalance() public {
        // drain faucet
        Faucet emptyFaucet = new Faucet(IERC20(address(token)), DRIP_AMOUNT, COOLDOWN);

        vm.prank(user1);
        vm.expectRevert("Faucet: insufficient balance");
        emptyFaucet.drip();
    }

    function test_drip_multipleUsers() public {
        vm.prank(user1);
        faucet.drip();

        vm.prank(user2);
        faucet.drip();

        assertEq(token.balanceOf(user1), DRIP_AMOUNT);
        assertEq(token.balanceOf(user2), DRIP_AMOUNT);
    }

    // ── dripTo ──────────────────────────────────────────────────────

    function test_dripTo_transfersToRecipient() public {
        faucet.dripTo(user1);
        assertEq(token.balanceOf(user1), DRIP_AMOUNT);
    }

    function test_dripTo_cooldownTracksRecipient() public {
        faucet.dripTo(user1);

        vm.expectRevert("Faucet: cooldown active");
        faucet.dripTo(user1);
    }

    function test_dripTo_callerCanDripToMultiple() public {
        faucet.dripTo(user1);
        faucet.dripTo(user2);

        assertEq(token.balanceOf(user1), DRIP_AMOUNT);
        assertEq(token.balanceOf(user2), DRIP_AMOUNT);
    }

    // ── setDripAmount ───────────────────────────────────────────────

    function test_setDripAmount_updates() public {
        faucet.setDripAmount(500 ether);
        assertEq(faucet.dripAmount(), 500 ether);
    }

    function test_setDripAmount_emitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit Faucet.DripAmountUpdated(500 ether);
        faucet.setDripAmount(500 ether);
    }

    function test_setDripAmount_revert_ifNotOwner() public {
        vm.prank(user1);
        vm.expectRevert("Faucet: not owner");
        faucet.setDripAmount(500 ether);
    }

    // ── setCooldown ─────────────────────────────────────────────────

    function test_setCooldown_updates() public {
        faucet.setCooldown(2 days);
        assertEq(faucet.cooldown(), 2 days);
    }

    function test_setCooldown_emitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit Faucet.CooldownUpdated(2 days);
        faucet.setCooldown(2 days);
    }

    function test_setCooldown_revert_ifNotOwner() public {
        vm.prank(user1);
        vm.expectRevert("Faucet: not owner");
        faucet.setCooldown(2 days);
    }

    // ── setOwner ────────────────────────────────────────────────────

    function test_setOwner_transfers() public {
        faucet.setOwner(user1);
        assertEq(faucet.owner(), user1);
    }

    function test_setOwner_emitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit Faucet.OwnerUpdated(user1);
        faucet.setOwner(user1);
    }

    function test_setOwner_revert_ifNotOwner() public {
        vm.prank(user1);
        vm.expectRevert("Faucet: not owner");
        faucet.setOwner(user1);
    }

    function test_setOwner_revert_ifZeroAddress() public {
        vm.expectRevert("Faucet: zero address");
        faucet.setOwner(address(0));
    }

    function test_setOwner_oldOwnerLosesAccess() public {
        faucet.setOwner(user1);

        vm.expectRevert("Faucet: not owner");
        faucet.setDripAmount(1);
    }

    // ── withdraw ────────────────────────────────────────────────────

    function test_withdraw_transfersToOwner() public {
        uint256 before = token.balanceOf(owner);
        faucet.withdraw(500 ether);
        assertEq(token.balanceOf(owner), before + 500 ether);
    }

    function test_withdraw_revert_ifNotOwner() public {
        vm.prank(user1);
        vm.expectRevert("Faucet: not owner");
        faucet.withdraw(500 ether);
    }

    function test_withdraw_fullBalance() public {
        faucet.withdraw(FAUCET_SUPPLY);
        assertEq(token.balanceOf(address(faucet)), 0);
    }
}
