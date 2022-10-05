// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {OneWayBondingCurve} from "./OneWayBondingCurve.sol";
import {IAaveEcosystemReserveController} from "./external/aave/IAaveEcosystemReserveController.sol";
import {AaveV2Ethereum} from "@aave-address-book/AaveV2Ethereum.sol";

/**
 * @title Payload to approve the One Way Bonding Curve to spend predetermined USDC amount
 * @author Llama
 * @notice Provides an execute function for Aave governance to execute
 * Governance Forum Post:
 * Snapshot:
 */
contract ProposalPayload {
    /********************************
     *   CONSTANTS AND IMMUTABLES   *
     ********************************/

    address public constant USDC_TOKEN = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant AUSDC_TOKEN = 0xBcca60bB61934080951369a648Fb03DF4F96263C;

    OneWayBondingCurve public immutable oneWayBondingCurve;

    uint256 public immutable usdcAmount;

    uint256 public immutable ausdcAmount;

    /*******************
     *   CONSTRUCTOR   *
     *******************/

    constructor(
        OneWayBondingCurve _oneWayBondingCurve,
        uint256 _usdcAmount,
        uint256 _ausdcAmount
    ) {
        oneWayBondingCurve = _oneWayBondingCurve;
        usdcAmount = _usdcAmount;
        ausdcAmount = _ausdcAmount;
    }

    /*****************
     *   FUNCTIONS   *
     *****************/

    /// @notice The AAVE governance executor calls this function to implement the proposal.
    function execute() external {
        // Transfer pre-defined amount of aUSDC tokens to this Proposal Payload contract
        // from AAVE Mainnet Reserve Factor
        IAaveEcosystemReserveController(AaveV2Ethereum.COLLECTOR_CONTROLLER).transfer(
            AaveV2Ethereum.COLLECTOR,
            AUSDC_TOKEN,
            address(this),
            ausdcAmount
        );

        // Redeem aUSDC tokens in this Proposal Payload contract for USDC tokens
        // and send to AAVE Mainnet Reserve Factor
        AaveV2Ethereum.POOL.withdraw(USDC_TOKEN, ausdcAmount, AaveV2Ethereum.COLLECTOR);

        // Approve the One Way Bonding Curve contract to spend pre-defined amount of USDC tokens
        // from AAVE Mainnet Reserve Factor. This is inclusive of the redeemed aUSDC tokens.
        IAaveEcosystemReserveController(AaveV2Ethereum.COLLECTOR_CONTROLLER).approve(
            AaveV2Ethereum.COLLECTOR,
            USDC_TOKEN,
            address(oneWayBondingCurve),
            usdcAmount
        );
    }
}
