// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ILock} from "../src/interfaces/ILock.sol";
import {NodeRegistry} from "../src/NodeRegistry.sol";
import {YellowToken} from "../src/Token.sol";
import {LockerTestBase} from "./Locker.t.sol";

/// @dev Runs all shared ILock tests against NodeRegistry.
contract NodeRegistryLockerTest is LockerTestBase {
    NodeRegistry vault;

    function setUp() public override {
        token = new YellowToken(treasury);
        vault = new NodeRegistry(address(token), UNLOCK_PERIOD);
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
// NodeRegistry-specific: constructor
// -------------------------------------------------------------------------
contract NodeRegistryConstructorTest is Test {
    function test_revert_ifAssetIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(ILock.InvalidAddress.selector));
        new NodeRegistry(address(0), 14 days);
    }

    function test_revert_ifUnlockPeriodIsZero() public {
        YellowToken t = new YellowToken(address(this));
        vm.expectRevert(abi.encodeWithSelector(ILock.InvalidAmount.selector));
        new NodeRegistry(address(t), 0);
    }

    function test_setsAssetAndPeriod() public {
        YellowToken t = new YellowToken(address(this));
        NodeRegistry v = new NodeRegistry(address(t), 14 days);
        assertEq(v.asset(), address(t));
        assertEq(v.ASSET(), address(t));
        assertEq(v.UNLOCK_PERIOD(), 14 days);
    }
}
