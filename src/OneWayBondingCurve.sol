// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {AggregatorV3Interface} from "./external/AggregatorV3Interface.sol";
import {FixedPointMathLib} from "@solmate/utils/FixedPointMathLib.sol";

/// @title OneWayBondingCurve
/// @author Llama
/// @notice One Way Bonding Curve to purchase discounted USDC for BAL upto a USDC Ceiling
contract OneWayBondingCurve {
    using SafeERC20 for IERC20;

    /********************************
     *   CONSTANTS AND IMMUTABLES   *
     ********************************/

    address public constant AAVE_MAINNET_RESERVE_FACTOR = 0x464C71f6c2F760DdA6093dCB91C24c39e5d6e18c;
    uint256 public constant BASIS_POINTS_GRANULARITY = 10_000;
    uint256 public constant BASIS_POINTS_ARBITRAGE_INCENTIVE = 50;

    IERC20 public constant BAL = IERC20(0xba100000625a3754423978a60c9317c58a424e3D);
    IERC20 public constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    AggregatorV3Interface public constant BAL_USD_FEED =
        AggregatorV3Interface(0xdF2917806E30300537aEB49A7663062F4d1F2b5F);

    uint256 public constant USDC_BASE = 10**6;
    uint256 public constant BAL_BASE = 10**18;

    /// @notice USDC Cap that has been approved by AAVE Governance
    uint256 public immutable usdcAmountCap;

    /*************************
     *   STORAGE VARIABLES   *
     *************************/

    /// @notice Cumulative USDC Purchased
    uint256 public totalUsdcPurchased;

    /// @notice Cumulative BAL Received
    uint256 public totalBalReceived;

    /**************
     *   EVENTS   *
     **************/

    event Purchase(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);

    /****************************
     *   ERRORS AND MODIFIERS   *
     ****************************/

    error OnlyNonZeroAmount();
    error NotEnoughUsdcToPurchase();
    error InvalidOracleAnswer();

    /*******************
     *   CONSTRUCTOR   *
     *******************/

    constructor(uint256 _usdcAmountCap) {
        usdcAmountCap = _usdcAmountCap;
    }

    /*****************
     *   FUNCTIONS   *
     *****************/

    /// @notice Purchase USDC for BAL
    /// @param amountIn Amount of BAL input
    /// @return amountOut Amount of USDC received
    /// @dev Purchaser has to approve BAL transfer before calling this function
    function purchase(uint256 amountIn) external returns (uint256 amountOut) {
        if (amountIn == 0) revert OnlyNonZeroAmount();

        amountOut = getAmountOut(amountIn);
        if (amountOut > availableUsdcToPurchase()) revert NotEnoughUsdcToPurchase();

        totalUsdcPurchased += amountOut;
        totalBalReceived += amountIn;

        // Execute the purchase
        BAL.safeTransferFrom(msg.sender, AAVE_MAINNET_RESERVE_FACTOR, amountIn);
        USDC.safeTransferFrom(AAVE_MAINNET_RESERVE_FACTOR, msg.sender, amountOut);

        emit Purchase(address(BAL), address(USDC), amountIn, amountOut);
    }

    /// @notice Returns how close to the USDC amount cap we are
    function availableUsdcToPurchase() public view returns (uint256) {
        return usdcAmountCap - totalUsdcPurchased;
    }

    /// @notice Returns amount of USDC that will be received after a bonding curve purchase of BAL
    /// @param amountIn the amount of BAL used to purchase
    /// @return amountOut the amount of USDC received
    function getAmountOut(uint256 amountIn) public view returns (uint256 amountOut) {
        // Normalizing input BAL amount from BAL decimals (18) to USDC decimals (6)
        uint256 normalizedAmountIn = normalizeFromBALDecimalsToUSDCDecimals(amountIn);
        // The actual USDC value of the input BAL amount
        uint256 usdcValueOfAmountIn = FixedPointMathLib.mulDivDown(getOraclePrice(), normalizedAmountIn, USDC_BASE);
        // The incentivized USDC value of the input BAL amount
        amountOut = FixedPointMathLib.mulDivDown(getBondingCurvePriceMultiplier(), usdcValueOfAmountIn, USDC_BASE);
    }

    /// @notice The peg price of the referenced oracle as USD per BAL
    /// @return value The peg value
    function getOraclePrice() public view returns (uint256 value) {
        (uint80 roundId, int256 price, , , uint80 answeredInRound) = BAL_USD_FEED.latestRoundData();
        if (price <= 0 || answeredInRound != roundId) revert InvalidOracleAnswer();
        // Normalizing output from Chainlink Oracle from Oracle decimals to USDC decimals (6)
        value = normalizeFromOracleDecimalstoUSDCDecimals(uint256(price));
    }

    /// @notice Normalize BAL decimals (18) to USDC decimals (6)
    function normalizeFromBALDecimalsToUSDCDecimals(uint256 amount) public pure returns (uint256) {
        return (amount * USDC_BASE) / BAL_BASE;
    }

    /// @notice Normalize BAL/USD Chainlink Oracle Feed decimals to USDC decimals (6)
    function normalizeFromOracleDecimalstoUSDCDecimals(uint256 amount) public view returns (uint256) {
        return (amount * USDC_BASE) / (10**uint256(BAL_USD_FEED.decimals()));
    }

    /// @notice The bonding curve price multiplier with arbitrage incentive
    function getBondingCurvePriceMultiplier() public pure returns (uint256) {
        return ((BASIS_POINTS_GRANULARITY + BASIS_POINTS_ARBITRAGE_INCENTIVE) * USDC_BASE) / BASIS_POINTS_GRANULARITY;
    }
}
