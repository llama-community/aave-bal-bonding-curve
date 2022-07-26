// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {OneWayBondingCurve} from "./OneWayBondingCurve.sol";
import {IEcosystemReserveController} from "./external/aave/IEcosystemReserveController.sol";

/// @title Payload to approve the One Way Bonding Curve to spend predetermined USDC amount
/// @author Llama
/// @notice Provides an execute function for Aave governance to execute
contract ProposalPayload {
    /********************************
     *   CONSTANTS AND IMMUTABLES   *
     ********************************/

    IEcosystemReserveController public constant AAVE_ECOSYSTEM_RESERVE_CONTROLLER =
        IEcosystemReserveController(0x3d569673dAa0575c936c7c67c4E6AedA69CC630C);

    address public constant AAVE_MAINNET_RESERVE_FACTOR = 0x464C71f6c2F760DdA6093dCB91C24c39e5d6e18c;

    address public constant USDC_TOKEN = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    OneWayBondingCurve public immutable oneWayBondingCurve;

    uint256 public immutable usdcAmount;

    /*******************
     *   CONSTRUCTOR   *
     *******************/

    constructor(OneWayBondingCurve _oneWayBondingCurve, uint256 _usdcAmount) {
        oneWayBondingCurve = _oneWayBondingCurve;
        usdcAmount = _usdcAmount;
    }

    /*****************
     *   FUNCTIONS   *
     *****************/

    /// @notice The AAVE governance executor calls this function to implement the proposal.
    function execute() external {
        // Approve the One Way Bonding Curve contract to spend pre-defined amount of USDC tokens
        AAVE_ECOSYSTEM_RESERVE_CONTROLLER.approve(
            AAVE_MAINNET_RESERVE_FACTOR,
            USDC_TOKEN,
            address(oneWayBondingCurve),
            usdcAmount
        );
    }
}
