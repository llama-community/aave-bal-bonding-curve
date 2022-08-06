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
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "../external/AggregatorV3Interface.sol";
import {ILendingPool} from "../external/aave/ILendingPool.sol";

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
    ILendingPool public constant AAVE_LENDING_POOL = ILendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);

    uint256 public constant USDC_BASE = 10**6;
    uint256 public constant BAL_BASE = 10**18;

    OneWayBondingCurve public oneWayBondingCurve;

    // USDC equivalent of ~100,000 BAL with 50bps incentive
    uint256 public constant USDC_AMOUNT_CAP = 603000e6;
    uint256 public constant AUSDC_AMOUNT = 250000e6;
    uint256 public constant BAL_AMOUNT_IN = 10000e18;
    address public constant BAL_WHALE = 0xF977814e90dA44bFA03b6295A0616a897441aceC;

    function setUp() public {
        oneWayBondingCurve = new OneWayBondingCurve(USDC_AMOUNT_CAP);

        vm.startPrank(AAVE_MAINNET_RESERVE_FACTOR);
        AAVE_LENDING_POOL.withdraw(address(USDC), AUSDC_AMOUNT, AAVE_MAINNET_RESERVE_FACTOR);
        // Now Aave Mainnet Reserve Factor will have enough USDC to meet USDC_AMOUNT_CAP
        USDC.approve(address(oneWayBondingCurve), USDC_AMOUNT_CAP);
        vm.stopPrank();

        vm.label(address(oneWayBondingCurve), "OneWayBondingCurve");
        vm.label(address(BAL), "BalToken");
        vm.label(address(USDC), "UsdcToken");
        vm.label(address(BAL_USD_FEED), "BalUsdChainlinkFeed");
        vm.label(AAVE_MAINNET_RESERVE_FACTOR, "AAVE_MAINNET_RESERVE_FACTOR");
    }

    function testApprovalBondingCurve() public {
        assertEq(USDC.allowance(AAVE_MAINNET_RESERVE_FACTOR, address(oneWayBondingCurve)), USDC_AMOUNT_CAP);
    }

    function testUsdcAmountCap() public {
        assertEq(oneWayBondingCurve.usdcAmountCap(), USDC_AMOUNT_CAP);
        assertLe(USDC_AMOUNT_CAP, USDC.balanceOf(AAVE_MAINNET_RESERVE_FACTOR));
    }

    function testGetBondingCurvePriceMultiplier() public {
        assertEq(
            oneWayBondingCurve.getBondingCurvePriceMultiplier(),
            ((BASIS_POINTS_GRANULARITY + BASIS_POINTS_ARBITRAGE_INCENTIVE) * USDC_BASE) / BASIS_POINTS_GRANULARITY
        );
        assertEq(oneWayBondingCurve.getBondingCurvePriceMultiplier(), 1005000);
    }

    function testZeroAmountOraclePrice() public {
        // Mocking returned value of Price = 0
        vm.mockCall(
            address(BAL_USD_FEED),
            abi.encodeWithSelector(BAL_USD_FEED.latestRoundData.selector),
            abi.encode(uint80(10), int256(0), uint256(2), uint256(3), uint80(10))
        );

        vm.expectRevert(OneWayBondingCurve.InvalidOracleAnswer.selector);
        oneWayBondingCurve.getOraclePrice();

        vm.clearMockedCalls();
    }

    function testNegativeAmountOraclePrice() public {
        // Mocking returned value of Price < 0
        vm.mockCall(
            address(BAL_USD_FEED),
            abi.encodeWithSelector(BAL_USD_FEED.latestRoundData.selector),
            abi.encode(uint80(10), int256(-1), uint256(2), uint256(3), uint80(10))
        );

        vm.expectRevert(OneWayBondingCurve.InvalidOracleAnswer.selector);
        oneWayBondingCurve.getOraclePrice();

        vm.clearMockedCalls();
    }

    function testRoundNotMatchingOraclePrice() public {
        // Mocking mismatched roundID and answeredInRound values that are returned
        vm.mockCall(
            address(BAL_USD_FEED),
            abi.encodeWithSelector(BAL_USD_FEED.latestRoundData.selector),
            abi.encode(uint80(10), int256(600000000), uint256(2), uint256(3), uint80(9))
        );

        vm.expectRevert(OneWayBondingCurve.InvalidOracleAnswer.selector);
        oneWayBondingCurve.getOraclePrice();

        vm.clearMockedCalls();
    }

    function testGetOraclePrice() public {
        assertEq(BAL_USD_FEED.decimals(), 8);
        (, int256 price, , , ) = BAL_USD_FEED.latestRoundData();
        assertEq(uint256(price), 597519904);
        assertEq(oneWayBondingCurve.normalizeFromOracleDecimalstoUSDCDecimals(uint256(price)), 5975199);
        assertEq(oneWayBondingCurve.getOraclePrice(), 5975199);
    }

    function testGetOraclePriceAtMultipleIntervals() public {
        // Testing for around 50000 blocks
        // BAL/USD Chainlink price feed updates every 24 hours ~= 6500 blocks
        for (uint256 i = 0; i < 5000; i++) {
            vm.roll(block.number - 10);
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

    function testPurchaseZeroAmount() public {
        vm.expectRevert(OneWayBondingCurve.OnlyNonZeroAmount.selector);
        oneWayBondingCurve.purchase(0);
    }

    function testPurchaseHitUSDCCeiling() public {
        vm.startPrank(BAL_WHALE);
        BAL.approve(address(oneWayBondingCurve), 95000e18);
        oneWayBondingCurve.purchase(95000e18);

        assertLe(oneWayBondingCurve.totalUsdcPurchased(), oneWayBondingCurve.usdcAmountCap());
        assertLe(oneWayBondingCurve.totalUsdcPurchased(), USDC_AMOUNT_CAP);

        BAL.approve(address(oneWayBondingCurve), BAL_AMOUNT_IN);
        vm.expectRevert(OneWayBondingCurve.NotEnoughUsdcToPurchase.selector);
        oneWayBondingCurve.purchase(BAL_AMOUNT_IN);
    }

    function testPurchase() public {
        vm.startPrank(BAL_WHALE);
        BAL.approve(address(oneWayBondingCurve), BAL_AMOUNT_IN);

        uint256 initialAaveMainnetReserverFactorUsdcBalance = USDC.balanceOf(AAVE_MAINNET_RESERVE_FACTOR);
        uint256 initialAaveMainnetReserverFactorBalBalance = BAL.balanceOf(AAVE_MAINNET_RESERVE_FACTOR);
        uint256 initialPurchaserUsdcBalance = USDC.balanceOf(BAL_WHALE);
        uint256 initialPurchaseBalBalance = BAL.balanceOf(BAL_WHALE);

        assertEq(oneWayBondingCurve.totalUsdcPurchased(), 0);
        assertEq(oneWayBondingCurve.totalBalReceived(), 0);

        vm.expectEmit(true, true, false, true);
        emit Purchase(address(BAL), address(USDC), BAL_AMOUNT_IN, 60050749950);
        uint256 usdcAmountOut = oneWayBondingCurve.purchase(BAL_AMOUNT_IN);

        assertEq(
            USDC.balanceOf(AAVE_MAINNET_RESERVE_FACTOR),
            initialAaveMainnetReserverFactorUsdcBalance - usdcAmountOut
        );
        assertEq(
            BAL.balanceOf(AAVE_MAINNET_RESERVE_FACTOR),
            initialAaveMainnetReserverFactorBalBalance + BAL_AMOUNT_IN
        );
        assertEq(USDC.balanceOf(BAL_WHALE), initialPurchaserUsdcBalance + usdcAmountOut);
        assertEq(BAL.balanceOf(BAL_WHALE), initialPurchaseBalBalance - BAL_AMOUNT_IN);
        assertEq(oneWayBondingCurve.totalUsdcPurchased(), usdcAmountOut);
        assertEq(oneWayBondingCurve.totalBalReceived(), BAL_AMOUNT_IN);
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

    function testInvalidPriceFromOracleFuzz(int256 price) public {
        vm.assume(price <= int256(0));

        // Mocking returned value of price <=0
        vm.mockCall(
            address(BAL_USD_FEED),
            abi.encodeWithSelector(BAL_USD_FEED.latestRoundData.selector),
            abi.encode(uint80(10), price, uint256(2), uint256(3), uint80(10))
        );

        vm.expectRevert(OneWayBondingCurve.InvalidOracleAnswer.selector);
        oneWayBondingCurve.getOraclePrice();

        vm.clearMockedCalls();
    }

    function testRoundNotMatchingFromOracleFuzz(uint80 roundId, uint80 answeredInRound) public {
        vm.assume(roundId != answeredInRound);

        // Mocking mismatched roundID and answeredInRound values that are returned
        vm.mockCall(
            address(BAL_USD_FEED),
            abi.encodeWithSelector(BAL_USD_FEED.latestRoundData.selector),
            abi.encode(roundId, int256(600000000), uint256(2), uint256(3), answeredInRound)
        );

        vm.expectRevert(OneWayBondingCurve.InvalidOracleAnswer.selector);
        oneWayBondingCurve.getOraclePrice();

        vm.clearMockedCalls();
    }

    function testGetAmountOutFuzz(uint256 amount) public {
        // Assuming reasonable Balancer amount upper bound of BAL Total Supply
        vm.assume(amount <= BAL.totalSupply());

        uint256 normalizedAmountIn = oneWayBondingCurve.normalizeFromBALDecimalsToUSDCDecimals(amount);
        uint256 usdcValueOfAmountIn = (oneWayBondingCurve.getOraclePrice() * normalizedAmountIn) / USDC_BASE;
        uint256 amountOut = (oneWayBondingCurve.getBondingCurvePriceMultiplier() * usdcValueOfAmountIn) / USDC_BASE;
        assertEq(oneWayBondingCurve.getAmountOut(amount), amountOut);
    }

    function testPurchaseFuzz(uint256 amount) public {
        // Assuming upper bound of purchase of ~100100 BAL
        vm.assume(amount > 0 && amount <= 100100e18);

        vm.startPrank(BAL_WHALE);
        BAL.approve(address(oneWayBondingCurve), amount);

        uint256 initialAaveMainnetReserverFactorUsdcBalance = USDC.balanceOf(AAVE_MAINNET_RESERVE_FACTOR);
        uint256 initialAaveMainnetReserverFactorBalBalance = BAL.balanceOf(AAVE_MAINNET_RESERVE_FACTOR);
        uint256 initialPurchaserUsdcBalance = USDC.balanceOf(BAL_WHALE);
        uint256 initialPurchaseBalBalance = BAL.balanceOf(BAL_WHALE);

        assertEq(oneWayBondingCurve.totalUsdcPurchased(), 0);
        assertEq(oneWayBondingCurve.totalBalReceived(), 0);

        uint256 usdcAmountOut = oneWayBondingCurve.purchase(amount);

        assertEq(
            USDC.balanceOf(AAVE_MAINNET_RESERVE_FACTOR),
            initialAaveMainnetReserverFactorUsdcBalance - usdcAmountOut
        );
        assertEq(BAL.balanceOf(AAVE_MAINNET_RESERVE_FACTOR), initialAaveMainnetReserverFactorBalBalance + amount);
        assertEq(USDC.balanceOf(BAL_WHALE), initialPurchaserUsdcBalance + usdcAmountOut);
        assertEq(BAL.balanceOf(BAL_WHALE), initialPurchaseBalBalance - amount);
        assertEq(oneWayBondingCurve.totalUsdcPurchased(), usdcAmountOut);
        assertEq(oneWayBondingCurve.totalBalReceived(), amount);
    }
}
