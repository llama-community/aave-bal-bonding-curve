// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

// testing libraries
import "@forge-std/Test.sol";

// contract dependencies
import {OneWayBondingCurve} from "../OneWayBondingCurve.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "../external/AggregatorV3Interface.sol";
import {AaveV2Ethereum} from "@aave-address-book/AaveV2Ethereum.sol";

contract OneWayBondingCurveTest is Test {
    event Purchase(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);

    address public immutable AAVE_MAINNET_RESERVE_FACTOR = AaveV2Ethereum.COLLECTOR;
    uint256 public constant BASIS_POINTS_GRANULARITY = 10_000;
    uint256 public constant BASIS_POINTS_ARBITRAGE_INCENTIVE = 50;

    IERC20 public constant BAL = IERC20(0xba100000625a3754423978a60c9317c58a424e3D);
    IERC20 public constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 public constant AUSDC = IERC20(0xBcca60bB61934080951369a648Fb03DF4F96263C);
    AggregatorV3Interface public constant BAL_USD_FEED =
        AggregatorV3Interface(0xdF2917806E30300537aEB49A7663062F4d1F2b5F);

    uint256 public constant USDC_BASE = 10**6;
    uint256 public constant BAL_BASE = 10**18;

    OneWayBondingCurve public oneWayBondingCurve;

    // USDC equivalent of ~100,000 BAL with 50bps incentive
    uint256 public constant AUSDC_AMOUNT_CAP = 603000e6;
    uint256 public constant BAL_AMOUNT_IN = 10000e18;
    address public constant BAL_WHALE = 0xF977814e90dA44bFA03b6295A0616a897441aceC;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 15777118);
        oneWayBondingCurve = new OneWayBondingCurve();
        vm.label(address(oneWayBondingCurve), "OneWayBondingCurve");
    }

    // function testGetBondingCurvePriceMultiplier() public {
    //     assertEq(
    //         oneWayBondingCurve.getBondingCurvePriceMultiplier(),
    //         ((BASIS_POINTS_GRANULARITY + BASIS_POINTS_ARBITRAGE_INCENTIVE) * USDC_BASE) / BASIS_POINTS_GRANULARITY
    //     );
    //     assertEq(oneWayBondingCurve.getBondingCurvePriceMultiplier(), 1005000);
    // }

    // function testZeroAmountOraclePrice() public {
    //     // Mocking returned value of Price = 0
    //     vm.mockCall(
    //         address(BAL_USD_FEED),
    //         abi.encodeWithSelector(BAL_USD_FEED.latestRoundData.selector),
    //         abi.encode(uint80(10), int256(0), uint256(2), uint256(3), uint80(10))
    //     );

    //     vm.expectRevert(OneWayBondingCurve.InvalidOracleAnswer.selector);
    //     oneWayBondingCurve.getOraclePrice();

    //     vm.clearMockedCalls();
    // }

    // function testNegativeAmountOraclePrice() public {
    //     // Mocking returned value of Price < 0
    //     vm.mockCall(
    //         address(BAL_USD_FEED),
    //         abi.encodeWithSelector(BAL_USD_FEED.latestRoundData.selector),
    //         abi.encode(uint80(10), int256(-1), uint256(2), uint256(3), uint80(10))
    //     );

    //     vm.expectRevert(OneWayBondingCurve.InvalidOracleAnswer.selector);
    //     oneWayBondingCurve.getOraclePrice();

    //     vm.clearMockedCalls();
    // }

    // function testRoundNotMatchingOraclePrice() public {
    //     // Mocking mismatched roundID and answeredInRound values that are returned
    //     vm.mockCall(
    //         address(BAL_USD_FEED),
    //         abi.encodeWithSelector(BAL_USD_FEED.latestRoundData.selector),
    //         abi.encode(uint80(10), int256(600000000), uint256(2), uint256(3), uint80(9))
    //     );

    //     vm.expectRevert(OneWayBondingCurve.InvalidOracleAnswer.selector);
    //     oneWayBondingCurve.getOraclePrice();

    //     vm.clearMockedCalls();
    // }

    // function testGetOraclePrice() public {
    //     assertEq(BAL_USD_FEED.decimals(), 8);
    //     (, int256 price, , , ) = BAL_USD_FEED.latestRoundData();
    //     assertEq(uint256(price), 597519904);
    //     assertEq(oneWayBondingCurve.normalizeFromOracleDecimalstoUSDCDecimals(uint256(price)), 5975199);
    //     assertEq(oneWayBondingCurve.getOraclePrice(), 5975199);
    // }

    // function testGetOraclePriceAtMultipleIntervals() public {
    //     // Testing for around 50000 blocks
    //     // BAL/USD Chainlink price feed updates every 24 hours ~= 6500 blocks
    //     for (uint256 i = 0; i < 5000; i++) {
    //         vm.roll(block.number - 10);
    //         (, int256 price, , , ) = BAL_USD_FEED.latestRoundData();
    //         assertEq(
    //             oneWayBondingCurve.getOraclePrice(),
    //             oneWayBondingCurve.normalizeFromOracleDecimalstoUSDCDecimals(uint256(price))
    //         );
    //     }
    // }

    // function testGetAmountOut() public {
    //     uint256 normalizedAmountIn = oneWayBondingCurve.normalizeFromBALDecimalsToUSDCDecimals(BAL_AMOUNT_IN);
    //     assertEq(normalizedAmountIn, 10000e6);
    //     uint256 oraclePrice = oneWayBondingCurve.getOraclePrice();
    //     assertEq(oraclePrice, 5975199);
    //     uint256 usdcValueOfAmountIn = (oraclePrice * normalizedAmountIn) / USDC_BASE;
    //     assertEq(usdcValueOfAmountIn, 59751990000);
    //     uint256 amountOut = (oneWayBondingCurve.getBondingCurvePriceMultiplier() * usdcValueOfAmountIn) / USDC_BASE;
    //     assertEq(amountOut, 60050749950);
    //     assertEq(oneWayBondingCurve.getAmountOut(BAL_AMOUNT_IN), 60050749950);
    // }

    // /*****************
    //  *   FUZZ TESTS  *
    //  *****************/

    // function testNormalizeFromBALDecimalsToUSDCDecimals(uint256 amount) public {
    //     // Assuming reasonable Balancer amount upper bound of BAL Total Supply
    //     vm.assume(amount <= BAL.totalSupply());

    //     assertEq(oneWayBondingCurve.normalizeFromBALDecimalsToUSDCDecimals(amount), (amount * USDC_BASE) / BAL_BASE);
    // }

    // function testNormalizeFromOracleDecimalstoUSDCDecimals(uint256 amount) public {
    //     // Assuming reasonable Balancer upper bound price of 1 BAL = $1 Million
    //     vm.assume(amount <= (1e6**uint256(BAL_USD_FEED.decimals())));

    //     assertEq(
    //         oneWayBondingCurve.normalizeFromOracleDecimalstoUSDCDecimals(amount),
    //         (amount * USDC_BASE) / (10**uint256(BAL_USD_FEED.decimals()))
    //     );
    // }

    // function testInvalidPriceFromOracleFuzz(int256 price) public {
    //     vm.assume(price <= int256(0));

    //     // Mocking returned value of price <=0
    //     vm.mockCall(
    //         address(BAL_USD_FEED),
    //         abi.encodeWithSelector(BAL_USD_FEED.latestRoundData.selector),
    //         abi.encode(uint80(10), price, uint256(2), uint256(3), uint80(10))
    //     );

    //     vm.expectRevert(OneWayBondingCurve.InvalidOracleAnswer.selector);
    //     oneWayBondingCurve.getOraclePrice();

    //     vm.clearMockedCalls();
    // }

    // function testRoundNotMatchingFromOracleFuzz(uint80 roundId, uint80 answeredInRound) public {
    //     vm.assume(roundId != answeredInRound);

    //     // Mocking mismatched roundID and answeredInRound values that are returned
    //     vm.mockCall(
    //         address(BAL_USD_FEED),
    //         abi.encodeWithSelector(BAL_USD_FEED.latestRoundData.selector),
    //         abi.encode(roundId, int256(600000000), uint256(2), uint256(3), answeredInRound)
    //     );

    //     vm.expectRevert(OneWayBondingCurve.InvalidOracleAnswer.selector);
    //     oneWayBondingCurve.getOraclePrice();

    //     vm.clearMockedCalls();
    // }

    // function testGetAmountOutFuzz(uint256 amount) public {
    //     // Assuming reasonable Balancer amount upper bound of BAL Total Supply
    //     vm.assume(amount <= BAL.totalSupply());

    //     uint256 normalizedAmountIn = oneWayBondingCurve.normalizeFromBALDecimalsToUSDCDecimals(amount);
    //     uint256 usdcValueOfAmountIn = (oneWayBondingCurve.getOraclePrice() * normalizedAmountIn) / USDC_BASE;
    //     uint256 amountOut = (oneWayBondingCurve.getBondingCurvePriceMultiplier() * usdcValueOfAmountIn) / USDC_BASE;
    //     assertEq(oneWayBondingCurve.getAmountOut(amount), amountOut);
    // }
}
