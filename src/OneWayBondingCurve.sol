// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Decimal} from "./external/Decimal.sol";
import {AggregatorV3Interface} from "./external/AggregatorV3Interface.sol";

/// @title OneWayBondingCurve
/// @author Llama
/// @notice One Way Bonding Curve to sell BAL into and buy USDC from
contract OneWayBondingCurve {
    using SafeERC20 for IERC20;
    using Decimal for Decimal.D256;

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

    uint256 public immutable usdcAmountCap;

    /*************************
     *   STORAGE VARIABLES   *
     *************************/

    uint256 public totalUsdcPurchased;
    uint256 public totalBalReceived;

    /**************
     *   EVENTS   *
     **************/

    event Purchase(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);

    /****************************
     *   ERRORS AND MODIFIERS   *
     ****************************/

    error UsdcAmountCapCrossed();
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
        amountOut = getAmountOut(amountIn);
        if (amountOut > availableUsdcToPurchase()) revert UsdcAmountCapCrossed();

        totalUsdcPurchased += amountOut;
        totalBalReceived += amountIn;

        // Execute the purchase
        BAL.safeTransferFrom(msg.sender, AAVE_MAINNET_RESERVE_FACTOR, amountIn);
        USDC.safeTransferFrom(AAVE_MAINNET_RESERVE_FACTOR, msg.sender, amountOut);

        emit Purchase(address(BAL), address(USDC), amountIn, amountOut);
    }

    /// @notice returns how close to the USDC amount cap we are
    function availableUsdcToPurchase() public view returns (uint256) {
        return usdcAmountCap - totalUsdcPurchased;
    }

    /// @notice Return amount of USDC received after a bonding curve purchase
    /// @param amountIn the amount of BAL used to purchase
    /// @return amountOut the amount of USDC received
    function getAmountOut(uint256 amountIn) public view returns (uint256 amountOut) {
        uint256 normalizedAmountIn = _normalizeBALDecimalsToUSDCDecimals(amountIn);
        // the actual USDC value of the input BAL amount
        uint256 usdcValueOfAmountIn = readOracle().mul(normalizedAmountIn).asUint256();
        // the incentivized USDC value of the input BAL amount
        amountOut = _getBondingCurvePriceMultiplier().mul(usdcValueOfAmountIn).asUint256();
    }

    /// @notice the peg price of the referenced oracle as USD per BAL
    /// @return value peg as a Decimal
    function readOracle() public view returns (Decimal.D256 memory value) {
        (uint80 roundId, int256 price, , , uint80 answeredInRound) = BAL_USD_FEED.latestRoundData();
        if (price <= 0 || answeredInRound != roundId) revert InvalidOracleAnswer();

        uint256 oracleDecimalsNormalizer = 10**uint256(BAL_USD_FEED.decimals());
        // Normalized oracle value
        value = Decimal.from(uint256(price)).div(oracleDecimalsNormalizer);
    }

    /// @notice The bonding curve price multiplier with arbitrage incentive
    function _getBondingCurvePriceMultiplier() private pure returns (Decimal.D256 memory) {
        return Decimal.ratio(BASIS_POINTS_GRANULARITY + BASIS_POINTS_ARBITRAGE_INCENTIVE, BASIS_POINTS_GRANULARITY);
    }

    function _normalizeBALDecimalsToUSDCDecimals(uint256 amount) private pure returns (uint256) {
        return (amount * (10**6)) / (10**18);
    }
}
