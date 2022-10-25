// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {AggregatorV3Interface} from "./external/AggregatorV3Interface.sol";
import {AaveV2Ethereum} from "@aave-address-book/AaveV2Ethereum.sol";

/// @title OneWayBondingCurve
/// @author Llama
/// @notice One Way Bonding Curve to purchase discounted USDC for BAL upto a 100k BAL Ceiling
contract OneWayBondingCurve {
    using SafeERC20 for IERC20;

    /********************************
     *   CONSTANTS AND IMMUTABLES   *
     ********************************/

    uint256 public constant BAL_AMOUNT_CAP = 100_000e18;

    IERC20 public constant BAL = IERC20(0xba100000625a3754423978a60c9317c58a424e3D);
    IERC20 public constant ABAL = IERC20(0x272F97b7a56a387aE942350bBC7Df5700f8a4576);
    IERC20 public constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 public constant AUSDC = IERC20(0xBcca60bB61934080951369a648Fb03DF4F96263C);

    AggregatorV3Interface public constant BAL_USD_FEED =
        AggregatorV3Interface(0xdF2917806E30300537aEB49A7663062F4d1F2b5F);

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
    event Deposit(address indexed token, address indexed aToken, uint256 amount);

    /****************************
     *   ERRORS AND MODIFIERS   *
     ****************************/

    error OnlyNonZeroAmount();
    error ExcessBalAmountIn();
    error BalCapNotFilled();
    error ZeroAllowance();
    error ZeroBalance();
    error InvalidOracleAnswer();

    /*****************
     *   FUNCTIONS   *
     *****************/

    /// @notice Purchase USDC for BAL
    /// @param amountIn Amount of BAL input
    /// @return amountOut Amount of USDC received
    /// @dev Purchaser has to approve BAL transfer before calling this function
    function purchase(uint256 amountIn) external returns (uint256 amountOut) {
        if (amountIn == 0) revert OnlyNonZeroAmount();
        if (amountIn > availableBalToBeFilled()) revert ExcessBalAmountIn();

        amountOut = getAmountOut(amountIn);
        if (amountOut == 0) revert OnlyNonZeroAmount();

        totalBalReceived += amountIn;
        totalUsdcPurchased += amountOut;

        // Execute the purchase
        BAL.safeTransferFrom(msg.sender, AaveV2Ethereum.COLLECTOR, amountIn);
        USDC.safeTransferFrom(AaveV2Ethereum.COLLECTOR, msg.sender, amountOut);

        emit Purchase(address(BAL), address(USDC), amountIn, amountOut);
    }

    /// @notice Returns how close to the 100k BAL amount cap we are
    function availableBalToBeFilled() public view returns (uint256) {
        return BAL_AMOUNT_CAP - totalBalReceived;
    }

    /// @notice Returns amount of USDC that will be received after a bonding curve purchase of BAL
    /// @param amountIn the amount of BAL used to purchase
    /// @return amountOutWithBonus the amount of USDC received with 50 bps incentive included
    function getAmountOut(uint256 amountIn) public view returns (uint256 amountOutWithBonus) {
        /** 
            The actual calculation is a collapsed version of this to prevent precision loss:
            => amountOut = (amountBALWei / 10^balDecimals) * (chainlinkPrice / chainlinkPrecision) * 10^usdcDecimals
            => amountOut = (amountBalWei / 10^18) * (chainlinkPrice / 10^8) * 10^6
         */
        uint256 amountOut = (amountIn * getOraclePrice()) / 10**20;
        // 50 bps arbitrage incentive
        amountOutWithBonus = (amountOut * 10050) / 10000;
    }

    /// @notice The peg price of the referenced oracle as USD per BAL
    function getOraclePrice() public view returns (uint256) {
        (, int256 price, , , ) = BAL_USD_FEED.latestRoundData();
        if (price <= 0) revert InvalidOracleAnswer();
        return uint256(price);
    }

    /// @notice Deposit remaining USDC in Aave V2 Collector after 100k BAL Amount Cap has been filled
    function depositUsdcCollector() external {
        uint256 usdcBalance = USDC.balanceOf(AaveV2Ethereum.COLLECTOR);
        uint256 usdcAllowance = USDC.allowance(AaveV2Ethereum.COLLECTOR, address(this));

        if (totalBalReceived < BAL_AMOUNT_CAP) revert BalCapNotFilled();
        if (usdcAllowance == 0) revert ZeroAllowance();
        if (usdcBalance == 0) revert ZeroBalance();

        // USDC available to Bonding Curve to spend on behalf of Aave V2 Collector
        uint256 usdcAmount = (usdcAllowance <= usdcBalance) ? usdcAllowance : usdcBalance;

        USDC.safeTransferFrom(AaveV2Ethereum.COLLECTOR, address(this), usdcAmount);
        USDC.approve(address(AaveV2Ethereum.POOL), usdcAmount);
        AaveV2Ethereum.POOL.deposit(address(USDC), usdcAmount, AaveV2Ethereum.COLLECTOR, 0);

        emit Deposit(address(USDC), address(AUSDC), usdcAmount);
    }

    /// @notice Deposit all acquired BAL after 100k BAL Amount Cap has been filled
    function depositBalCollector() external {
        uint256 balBalance = BAL.balanceOf(AaveV2Ethereum.COLLECTOR);
        uint256 balAllowance = BAL.allowance(AaveV2Ethereum.COLLECTOR, address(this));

        if (totalBalReceived < BAL_AMOUNT_CAP) revert BalCapNotFilled();
        if (balAllowance == 0) revert ZeroAllowance();
        if (balBalance == 0) revert ZeroBalance();

        // BAL available to Bonding Curve to spend on behalf of Aave V2 Collector
        uint256 balAmount = (balAllowance <= balBalance) ? balAllowance : balBalance;

        BAL.safeTransferFrom(AaveV2Ethereum.COLLECTOR, address(this), balAmount);
        BAL.approve(address(AaveV2Ethereum.POOL), balAmount);
        AaveV2Ethereum.POOL.deposit(address(BAL), balAmount, AaveV2Ethereum.COLLECTOR, 0);

        emit Deposit(address(BAL), address(ABAL), balAmount);
    }

    /// @notice Transfer any tokens accidentally sent to this contract to Aave V2 Collector
    /// @param tokens List of token addresses
    function rescueTokens(address[] memory tokens) external {
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).safeTransfer(AaveV2Ethereum.COLLECTOR, IERC20(tokens[i]).balanceOf(address(this)));
        }
    }
}
