// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";
import {OneWayBondingCurve} from "../src/OneWayBondingCurve.sol";
import {ProposalPayload} from "../src/ProposalPayload.sol";

contract DeployProposalPayload is Script {
    uint256 private constant usdcAmount = 603000e6;
    uint256 private constant ausdcAmount = 250000e6;

    function run() external {
        vm.startBroadcast();
        OneWayBondingCurve oneWayBondingCurve = new OneWayBondingCurve(usdcAmount);
        console.log("One Way Bonding Curve address", address(oneWayBondingCurve));
        ProposalPayload proposalPayload = new ProposalPayload(oneWayBondingCurve, usdcAmount, ausdcAmount);
        console.log("Proposal Payload address", address(proposalPayload));
        vm.stopBroadcast();
    }
}
