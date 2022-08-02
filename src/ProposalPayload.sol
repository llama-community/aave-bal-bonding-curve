// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {OneWayBondingCurve} from "./OneWayBondingCurve.sol";
import {IEcosystemReserveController} from "./external/aave/IEcosystemReserveController.sol";
import {ILendingPool} from "./external/aave/ILendingPool.sol";

/// @title Payload to approve the One Way Bonding Curve to spend predetermined USDC amount
/// @author Llama
/// @notice Provides an execute function for Aave governance to execute
contract ProposalPayload {
    /********************************
     *   CONSTANTS AND IMMUTABLES   *
     ********************************/

    IEcosystemReserveController public constant AAVE_ECOSYSTEM_RESERVE_CONTROLLER =
        IEcosystemReserveController(0x3d569673dAa0575c936c7c67c4E6AedA69CC630C);

    ILendingPool public constant AAVE_LENDING_POOL = ILendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);

    address public constant AAVE_MAINNET_RESERVE_FACTOR = 0x464C71f6c2F760DdA6093dCB91C24c39e5d6e18c;

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
        AAVE_ECOSYSTEM_RESERVE_CONTROLLER.transfer(
            AAVE_MAINNET_RESERVE_FACTOR,
            AUSDC_TOKEN,
            address(this),
            ausdcAmount
        );

        // Redeem aUSDC tokens in this Proposal Payload contract for USDC tokens
        // and send to AAVE Mainnet Reserve Factor
        AAVE_LENDING_POOL.withdraw(USDC_TOKEN, ausdcAmount, AAVE_MAINNET_RESERVE_FACTOR);

        // Approve the One Way Bonding Curve contract to spend pre-defined amount of USDC tokens
        // from AAVE Mainnet Reserve Factor. This is inclusive of the redeemed aUSDC tokens.
        AAVE_ECOSYSTEM_RESERVE_CONTROLLER.approve(
            AAVE_MAINNET_RESERVE_FACTOR,
            USDC_TOKEN,
            address(oneWayBondingCurve),
            usdcAmount
        );
    }
}
