// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

// testing libraries
import "@ds/test.sol";
import "@std/console.sol";
import {stdCheats} from "@std/stdlib.sol";
import {Vm} from "@std/Vm.sol";
import {DSTestPlus} from "@solmate/test/utils/DSTestPlus.sol";

// contract dependencies
import "../OneWayBondingCurve.sol";

contract OneWayBondingCurveTest is DSTestPlus, stdCheats {
    Vm private vm = Vm(HEVM_ADDRESS);
    OneWayBondingCurve public oneWayBondingCurve;
    uint256 public constant USDC_AMOUNT_CAP = 600000e6;

    function setUp() public {
        oneWayBondingCurve = new OneWayBondingCurve(USDC_AMOUNT_CAP);
        vm.label(address(oneWayBondingCurve), "OneWayBondingCurve");
    }
}
