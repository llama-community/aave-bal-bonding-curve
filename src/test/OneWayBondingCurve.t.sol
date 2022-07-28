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

    function testGetAmountOut() public {
        assertEq(oneWayBondingCurve.getAmountOut(BAL_AMOUNT_IN), 60050749950);
    }

    function testGetOraclePrice() public {
        assertEq(oneWayBondingCurve.getOraclePrice(), 5975199);
    }

    function testNormalizeFromBALDecimalsToUSDCDecimals() public {
        assertEq(oneWayBondingCurve.normalizeFromBALDecimalsToUSDCDecimals(BAL_AMOUNT_IN), 10000e6);
    }

    function testNormalizeFromOracleDecimalstoUSDCDecimals() public {
        assertEq(BAL_USD_FEED.decimals(), 8);
        (, int256 price, , , ) = BAL_USD_FEED.latestRoundData();
        assertEq(uint256(price), 597519904);
        assertEq(oneWayBondingCurve.normalizeFromOracleDecimalstoUSDCDecimals(uint256(price)), 5975199);
    }

    function testGetBondingCurvePriceMultiplier() public {
        assertEq(oneWayBondingCurve.getBondingCurvePriceMultiplier(), 1005000);
    }
}
