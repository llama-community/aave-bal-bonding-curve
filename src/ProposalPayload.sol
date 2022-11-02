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
    address public constant BAL_TOKEN = 0xba100000625a3754423978a60c9317c58a424e3D;
    uint256 public constant BAL_AMOUNT = 300_000e18;

    OneWayBondingCurve public immutable oneWayBondingCurve;
    uint256 public immutable ausdcAmount;
    uint256 public immutable usdcAmount;

    /*******************
     *   CONSTRUCTOR   *
     *******************/

    constructor(
        OneWayBondingCurve _oneWayBondingCurve,
        uint256 _ausdcAmount,
        uint256 _usdcAmount
    ) {
        oneWayBondingCurve = _oneWayBondingCurve;
        ausdcAmount = _ausdcAmount;
        usdcAmount = _usdcAmount;
    }

    /*****************
     *   FUNCTIONS   *
     *****************/

    /// @notice The AAVE governance executor calls this function to implement the proposal.
    function execute() external {
        // 1. Transfer pre-defined amount of aUSDC tokens to this Proposal Payload contract from AAVE V2 Collector
        IAaveEcosystemReserveController(AaveV2Ethereum.COLLECTOR_CONTROLLER).transfer(
            AaveV2Ethereum.COLLECTOR,
            AUSDC_TOKEN,
            address(this),
            ausdcAmount
        );

        // 2. Redeem aUSDC tokens in this Proposal Payload contract for USDC tokens and send to AAVE V2 Collector
        AaveV2Ethereum.POOL.withdraw(USDC_TOKEN, ausdcAmount, AaveV2Ethereum.COLLECTOR);

        // 3. Approve the One Way Bonding Curve contract to spend pre-defined amount of USDC tokens from AAVE V2 Collector
        IAaveEcosystemReserveController(AaveV2Ethereum.COLLECTOR_CONTROLLER).approve(
            AaveV2Ethereum.COLLECTOR,
            USDC_TOKEN,
            address(oneWayBondingCurve),
            usdcAmount
        );

        // 4. Approve the One Way Bonding Curve contract to spend 300K BAL from AAVE V2 Collector
        // 300K BAL = 200K BAL currently in AAVE V2 Collector + 100K BAL to be acquired through Bonding Curve
        IAaveEcosystemReserveController(AaveV2Ethereum.COLLECTOR_CONTROLLER).approve(
            AaveV2Ethereum.COLLECTOR,
            BAL_TOKEN,
            address(oneWayBondingCurve),
            BAL_AMOUNT
        );
    }
}
