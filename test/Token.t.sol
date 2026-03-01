// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {YellowToken} from "../src/Token.sol";

contract YellowTokenTest is Test {
    YellowToken token;
    address treasury = address(2);

    function setUp() public {
        token = new YellowToken(treasury);
    }

    function test_constructor_revert_ifTreasuryIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(YellowToken.InvalidAddress.selector));
        new YellowToken(address(0));
    }

    function test_constructor_nameAndSymbol() public view {
        assertEq(token.name(), "Yellow");
        assertEq(token.symbol(), "YELLOW");
    }

    function test_constructor_decimals() public view {
        assertEq(token.decimals(), 18);
    }

    function test_constructor_supplyMintedToTreasury() public view {
        assertEq(token.balanceOf(treasury), token.SUPPLY_CAP());
    }

    function test_supplyCap() public view {
        assertEq(token.SUPPLY_CAP(), 10_000_000_000 ether);
        assertEq(token.totalSupply(), 10_000_000_000 ether);
    }
}
