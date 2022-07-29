// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

// testing libraries
import "@ds/test.sol";
import "@std/console.sol";
import {stdCheats} from "@std/stdlib.sol";
import {Vm} from "@std/Vm.sol";
import {DSTestPlus} from "@solmate/test/utils/DSTestPlus.sol";

// contract dependencies
import "../OneWayBondingCurve.sol";

contract OneWayBondingCurveTest is DSTestPlus, stdCheats {
    event Purchase(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);

    Vm private vm = Vm(HEVM_ADDRESS);

    address public constant AAVE_MAINNET_RESERVE_FACTOR = 0x464C71f6c2F760DdA6093dCB91C24c39e5d6e18c;
    uint256 public constant BASIS_POINTS_GRANULARITY = 10_000;
    uint256 public constant BASIS_POINTS_ARBITRAGE_INCENTIVE = 50;

    IERC20 public constant BAL = IERC20(0xba100000625a3754423978a60c9317c58a424e3D);
    IERC20 public constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    AggregatorV3Interface public constant BAL_USD_FEED =
        AggregatorV3Interface(0xdF2917806E30300537aEB49A7663062F4d1F2b5F);

    uint256 public constant USDC_BASE = 10**6;
    uint256 public constant BAL_BASE = 10**18;

    OneWayBondingCurve public oneWayBondingCurve;

    uint256 public constant USDC_AMOUNT_CAP = 600000e6;
    uint256 public constant BAL_AMOUNT_IN = 10000e18;

    function setUp() public {
        oneWayBondingCurve = new OneWayBondingCurve(USDC_AMOUNT_CAP);
        vm.label(address(oneWayBondingCurve), "OneWayBondingCurve");
    }

    function testGetBondingCurvePriceMultiplier() public {
        assertEq(
            oneWayBondingCurve.getBondingCurvePriceMultiplier(),
            ((BASIS_POINTS_GRANULARITY + BASIS_POINTS_ARBITRAGE_INCENTIVE) * USDC_BASE) / BASIS_POINTS_GRANULARITY
        );
        assertEq(oneWayBondingCurve.getBondingCurvePriceMultiplier(), 1005000);
    }

    function testGetOraclePrice() public {
        assertEq(BAL_USD_FEED.decimals(), 8);
        (, int256 price, , , ) = BAL_USD_FEED.latestRoundData();
        assertEq(uint256(price), 597519904);
        assertEq(oneWayBondingCurve.normalizeFromOracleDecimalstoUSDCDecimals(uint256(price)), 5975199);
        assertEq(oneWayBondingCurve.getOraclePrice(), 5975199);
    }

    function testGetOraclePriceAtMultipleIntervals() public {
        for (uint256 i = 0; i < 5000; i++) {
            vm.roll(block.number + i);
            (, int256 price, , , ) = BAL_USD_FEED.latestRoundData();
            assertEq(
                oneWayBondingCurve.getOraclePrice(),
                oneWayBondingCurve.normalizeFromOracleDecimalstoUSDCDecimals(uint256(price))
            );
        }
    }

    function testGetAmountOut() public {
        uint256 normalizedAmountIn = oneWayBondingCurve.normalizeFromBALDecimalsToUSDCDecimals(BAL_AMOUNT_IN);
        assertEq(normalizedAmountIn, 10000e6);
        uint256 oraclePrice = oneWayBondingCurve.getOraclePrice();
        assertEq(oraclePrice, 5975199);
        uint256 usdcValueOfAmountIn = (oraclePrice * normalizedAmountIn) / USDC_BASE;
        assertEq(usdcValueOfAmountIn, 59751990000);
        uint256 amountOut = (oneWayBondingCurve.getBondingCurvePriceMultiplier() * usdcValueOfAmountIn) / USDC_BASE;
        assertEq(amountOut, 60050749950);
        assertEq(oneWayBondingCurve.getAmountOut(BAL_AMOUNT_IN), 60050749950);
    }

    /*****************
     *   FUZZ TESTS  *
     *****************/

    function testNormalizeFromBALDecimalsToUSDCDecimals(uint256 amount) public {
        // Assuming reasonable Balancer amount upper bound of BAL Total Supply
        vm.assume(amount <= BAL.totalSupply());

        assertEq(oneWayBondingCurve.normalizeFromBALDecimalsToUSDCDecimals(amount), (amount * USDC_BASE) / BAL_BASE);
    }

    function testNormalizeFromOracleDecimalstoUSDCDecimals(uint256 amount) public {
        // Assuming reasonable Balancer upper bound price of 1 BAL = $1 Million
        vm.assume(amount <= (1e6**uint256(BAL_USD_FEED.decimals())));

        assertEq(
            oneWayBondingCurve.normalizeFromOracleDecimalstoUSDCDecimals(amount),
            (amount * USDC_BASE) / (10**uint256(BAL_USD_FEED.decimals()))
        );
    }

    function testGetAmountOutFuzz(uint256 amount) public {
        // Assuming reasonable Balancer amount upper bound of BAL Total Supply
        vm.assume(amount <= BAL.totalSupply());

        uint256 normalizedAmountIn = oneWayBondingCurve.normalizeFromBALDecimalsToUSDCDecimals(amount);
        uint256 usdcValueOfAmountIn = (oneWayBondingCurve.getOraclePrice() * normalizedAmountIn) / USDC_BASE;
        uint256 amountOut = (oneWayBondingCurve.getBondingCurvePriceMultiplier() * usdcValueOfAmountIn) / USDC_BASE;
        assertEq(oneWayBondingCurve.getAmountOut(amount), amountOut);
    }
}
