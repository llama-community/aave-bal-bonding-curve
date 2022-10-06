// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {OneWayBondingCurve} from "./OneWayBondingCurve.sol";
import {IAaveEcosystemReserveController} from "./external/aave/IAaveEcosystemReserveController.sol";
import {AaveV2Ethereum} from "@aave-address-book/AaveV2Ethereum.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

/**
 * @title Payload to approve the One Way Bonding Curve to spend predetermined USDC amount
 * @author Llama
 * @notice Provides an execute function for Aave governance to execute
 * Governance Forum Post: https://governance.aave.com/t/arc-strategic-partnership-with-balancer-part-2/7813
 * Snapshot: https://snapshot.org/#/aave.eth/proposal/QmVqWgpRmoEvvhvXZFepmAgYU5ZK9XpSs39MExEUpiJZw3
 */
contract ProposalPayload {
    /********************************
     *   CONSTANTS AND IMMUTABLES   *
     ********************************/

    address public constant USDC_TOKEN = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant AUSDC_TOKEN = 0xBcca60bB61934080951369a648Fb03DF4F96263C;

    OneWayBondingCurve public immutable oneWayBondingCurve;
    uint256 public immutable ausdcAmount;

    /*******************
     *   CONSTRUCTOR   *
     *******************/

    constructor(OneWayBondingCurve _oneWayBondingCurve, uint256 _ausdcAmount) {
        oneWayBondingCurve = _oneWayBondingCurve;
        ausdcAmount = _ausdcAmount;
    }

    /*****************
     *   FUNCTIONS   *
     *****************/

    /// @notice The AAVE governance executor calls this function to implement the proposal.
    function execute() external {
        // Transfer all existing USDC tokens to this Proposal Payload contract from AAVE V2 Collector
        IAaveEcosystemReserveController(AaveV2Ethereum.COLLECTOR_CONTROLLER).transfer(
            AaveV2Ethereum.COLLECTOR,
            USDC_TOKEN,
            address(this),
            IERC20(USDC_TOKEN).balanceOf(AaveV2Ethereum.COLLECTOR)
        );

        uint256 usdcBalance = IERC20(USDC_TOKEN).balanceOf(address(this));

        // Approving transfer of all available USDC in Proposal Payload contract
        IERC20(USDC_TOKEN).approve(address(AaveV2Ethereum.POOL), usdcBalance);

        // Depositing all available USDC on behalf of AAVE V2 Collector to generate yield
        AaveV2Ethereum.POOL.deposit(USDC_TOKEN, usdcBalance, AaveV2Ethereum.COLLECTOR, 0);

        // Approve the One Way Bonding Curve contract to spend pre-defined amount of aUSDC tokens from AAVE V2 Collector
        IAaveEcosystemReserveController(AaveV2Ethereum.COLLECTOR_CONTROLLER).approve(
            AaveV2Ethereum.COLLECTOR,
            AUSDC_TOKEN,
            address(oneWayBondingCurve),
            ausdcAmount
        );
    }
}
