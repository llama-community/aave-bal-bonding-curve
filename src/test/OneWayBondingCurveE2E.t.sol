// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

// testing libraries
import "@forge-std/Test.sol";

// contract dependencies
import {GovHelpers} from "@aave-helpers/GovHelpers.sol";
import {ProposalPayload} from "../ProposalPayload.sol";
import {OneWayBondingCurve} from "../OneWayBondingCurve.sol";
import {DeployMainnetProposal} from "../../script/DeployMainnetProposal.s.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {AaveV2Ethereum} from "@aave-address-book/AaveV2Ethereum.sol";
import {AggregatorV3Interface} from "../external/AggregatorV3Interface.sol";

contract OneWayBondingCurveE2ETest is Test {
    event Purchase(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
    event Deposit(address indexed token, address indexed aToken, uint256 amount);

    address public constant AAVE_WHALE = 0xBE0eB53F46cd790Cd13851d5EFf43D12404d33E8;
    address public constant BAL_WHALE = 0xF977814e90dA44bFA03b6295A0616a897441aceC;
    address public constant USDC_WHALE = 0x55FE002aefF02F77364de339a1292923A15844B8;
    address public constant ETH_WHALE = 0xF977814e90dA44bFA03b6295A0616a897441aceC;

    uint256 public proposalId;

    uint256 public constant BASIS_POINTS_GRANULARITY = 10_000;
    uint256 public constant BASIS_POINTS_ARBITRAGE_INCENTIVE = 50;

    IERC20 public constant BAL = IERC20(0xba100000625a3754423978a60c9317c58a424e3D);
    IERC20 public constant ABAL = IERC20(0x272F97b7a56a387aE942350bBC7Df5700f8a4576);
    IERC20 public constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 public constant AUSDC = IERC20(0xBcca60bB61934080951369a648Fb03DF4F96263C);

    AggregatorV3Interface public constant BAL_USD_FEED =
        AggregatorV3Interface(0xdF2917806E30300537aEB49A7663062F4d1F2b5F);

    uint256 public constant USDC_BASE = 10**6;
    uint256 public constant BAL_BASE = 10**18;

    uint256 public constant AUSDC_AMOUNT = 350_000e6;
    uint256 public constant USDC_AMOUNT = 700_000e6;
    uint256 public constant BAL_AMOUNT_IN = 10_000e18;

    OneWayBondingCurve public oneWayBondingCurve;
    ProposalPayload public proposalPayload;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 15790293);

        // Deploying One Way Bonding Curve
        oneWayBondingCurve = new OneWayBondingCurve();

        // Deploy Payload
        proposalPayload = new ProposalPayload(oneWayBondingCurve, AUSDC_AMOUNT, USDC_AMOUNT);

        // Create Proposal
        vm.prank(AAVE_WHALE);
        proposalId = DeployMainnetProposal._deployMainnetProposal(
            address(proposalPayload),
            0x344d3181f08b3186228b93bac0005a3a961238164b8b06cbb5f0428a9180b8a7 // TODO: Replace with actual IPFS Hash
        );

        vm.label(address(oneWayBondingCurve), "OneWayBondingCurve");
        vm.label(address(proposalPayload), "ProposalPayload");
    }

    function testExecuteProposal() public {
        uint256 initialAusdcBalance = AUSDC.balanceOf(AaveV2Ethereum.COLLECTOR);
        uint256 initialUsdcBalance = USDC.balanceOf(AaveV2Ethereum.COLLECTOR);

        assertEq(AUSDC.balanceOf(address(proposalPayload)), 0);
        assertEq(USDC.balanceOf(address(proposalPayload)), 0);
        assertEq(AUSDC.allowance(AaveV2Ethereum.COLLECTOR, address(oneWayBondingCurve)), 0);
        assertEq(USDC.allowance(AaveV2Ethereum.COLLECTOR, address(oneWayBondingCurve)), 0);
        assertEq(BAL.allowance(AaveV2Ethereum.COLLECTOR, address(oneWayBondingCurve)), 0);

        // Pass vote and execute proposal
        GovHelpers.passVoteAndExecute(vm, proposalId);

        // AAVE Mainnet Reserve Factor gets some additional aTokens minted to it while depositing/withdrawing
        // https://github.com/aave/protocol-v2/blob/baeb455fad42d3160d571bd8d3a795948b72dd85/contracts/protocol/libraries/logic/ReserveLogic.sol#L265-L325
        assertGe(AUSDC.balanceOf(AaveV2Ethereum.COLLECTOR), initialAusdcBalance - AUSDC_AMOUNT);
        assertEq(USDC.balanceOf(AaveV2Ethereum.COLLECTOR), initialUsdcBalance + AUSDC_AMOUNT);
        assertEq(AUSDC.balanceOf(address(proposalPayload)), 0);
        assertEq(USDC.balanceOf(address(proposalPayload)), 0);
        assertEq(AUSDC.allowance(AaveV2Ethereum.COLLECTOR, address(oneWayBondingCurve)), 0);
        assertEq(USDC.allowance(AaveV2Ethereum.COLLECTOR, address(oneWayBondingCurve)), USDC_AMOUNT);
        assertEq(
            BAL.allowance(AaveV2Ethereum.COLLECTOR, address(oneWayBondingCurve)),
            oneWayBondingCurve.BAL_AMOUNT_CAP()
        );
    }

    // /************************************
    //  *   POST PROPOSAL EXECUTION TESTS  *
    //  ************************************/

    function testUsdcAmount() public {
        // Pass vote and execute proposal
        GovHelpers.passVoteAndExecute(vm, proposalId);

        assertLe(USDC_AMOUNT, USDC.balanceOf(AaveV2Ethereum.COLLECTOR));
    }

    function testPurchaseZeroAmount() public {
        // Pass vote and execute proposal
        GovHelpers.passVoteAndExecute(vm, proposalId);

        vm.expectRevert(OneWayBondingCurve.OnlyNonZeroAmount.selector);
        oneWayBondingCurve.purchase(0);
    }

    function testPurchaseHitBalCeiling() public {
        // Pass vote and execute proposal
        GovHelpers.passVoteAndExecute(vm, proposalId);

        // totalBalReceived is storage slot 1
        // Setting current totalBalReceived to 95k BAL
        vm.store(address(oneWayBondingCurve), bytes32(uint256(1)), bytes32(uint256(95_000e18)));

        assertEq(oneWayBondingCurve.totalBalReceived(), 95000e18);
        assertLe(oneWayBondingCurve.totalBalReceived(), oneWayBondingCurve.BAL_AMOUNT_CAP());

        vm.startPrank(BAL_WHALE);
        BAL.approve(address(oneWayBondingCurve), BAL_AMOUNT_IN);
        vm.expectRevert(OneWayBondingCurve.ExcessBalAmountIn.selector);
        oneWayBondingCurve.purchase(BAL_AMOUNT_IN);
        vm.stopPrank();
    }

    function testPurchase() public {
        // Pass vote and execute proposal
        GovHelpers.passVoteAndExecute(vm, proposalId);

        vm.startPrank(BAL_WHALE);
        BAL.approve(address(oneWayBondingCurve), BAL_AMOUNT_IN);

        uint256 initialCollectorUsdcBalance = USDC.balanceOf(AaveV2Ethereum.COLLECTOR);
        uint256 initialCollectorBalBalance = BAL.balanceOf(AaveV2Ethereum.COLLECTOR);
        uint256 initialPurchaserUsdcBalance = USDC.balanceOf(BAL_WHALE);
        uint256 initialPurchaserBalBalance = BAL.balanceOf(BAL_WHALE);

        assertEq(oneWayBondingCurve.totalUsdcPurchased(), 0);
        assertEq(oneWayBondingCurve.totalBalReceived(), 0);

        vm.expectEmit(true, true, false, true);
        emit Purchase(address(BAL), address(USDC), BAL_AMOUNT_IN, 60734568934);
        uint256 usdcAmountOut = oneWayBondingCurve.purchase(BAL_AMOUNT_IN);

        assertEq(USDC.balanceOf(AaveV2Ethereum.COLLECTOR), initialCollectorUsdcBalance - usdcAmountOut);
        assertEq(BAL.balanceOf(AaveV2Ethereum.COLLECTOR), initialCollectorBalBalance + BAL_AMOUNT_IN);
        assertEq(USDC.balanceOf(BAL_WHALE), initialPurchaserUsdcBalance + usdcAmountOut);
        assertEq(BAL.balanceOf(BAL_WHALE), initialPurchaserBalBalance - BAL_AMOUNT_IN);
        assertEq(oneWayBondingCurve.totalUsdcPurchased(), usdcAmountOut);
        assertEq(oneWayBondingCurve.totalBalReceived(), BAL_AMOUNT_IN);
    }

    function testDepositUsdcCollectorBalCapNotFilled() public {
        // Pass vote and execute proposal
        GovHelpers.passVoteAndExecute(vm, proposalId);

        uint256 amount = 90_000e18;

        vm.startPrank(BAL_WHALE);
        BAL.approve(address(oneWayBondingCurve), amount);
        oneWayBondingCurve.purchase(amount);
        vm.stopPrank();

        vm.expectRevert(OneWayBondingCurve.BalCapNotFilled.selector);
        oneWayBondingCurve.depositUsdcCollector();
    }

    function testDepositUsdcCollectorZeroAllowance() public {
        // Pass vote and execute proposal
        GovHelpers.passVoteAndExecute(vm, proposalId);

        // Filling out 100k BAL CAP
        vm.startPrank(BAL_WHALE);
        BAL.approve(address(oneWayBondingCurve), oneWayBondingCurve.BAL_AMOUNT_CAP());
        oneWayBondingCurve.purchase(oneWayBondingCurve.BAL_AMOUNT_CAP());
        vm.stopPrank();

        // Depositing all remaining USDC in Collector to make allowance 0
        oneWayBondingCurve.depositUsdcCollector();

        // Trying Deposit again
        vm.expectRevert(OneWayBondingCurve.ZeroAllowance.selector);
        oneWayBondingCurve.depositUsdcCollector();
    }

    function testDepositUsdcCollectorZeroBalance() public {
        // Pass vote and execute proposal
        GovHelpers.passVoteAndExecute(vm, proposalId);

        // Filling out 100k BAL CAP
        vm.startPrank(BAL_WHALE);
        BAL.approve(address(oneWayBondingCurve), oneWayBondingCurve.BAL_AMOUNT_CAP());
        oneWayBondingCurve.purchase(oneWayBondingCurve.BAL_AMOUNT_CAP());
        vm.stopPrank();

        // Transferring out remaining USDC in Collector
        vm.startPrank(AaveV2Ethereum.COLLECTOR);
        USDC.transfer(address(this), USDC.balanceOf(AaveV2Ethereum.COLLECTOR));

        vm.expectRevert(OneWayBondingCurve.ZeroBalance.selector);
        oneWayBondingCurve.depositUsdcCollector();
    }

    function testDepositUsdcCollector() public {
        // Pass vote and execute proposal
        GovHelpers.passVoteAndExecute(vm, proposalId);

        // Filling out 100k BAL CAP
        vm.startPrank(BAL_WHALE);
        BAL.approve(address(oneWayBondingCurve), oneWayBondingCurve.BAL_AMOUNT_CAP());
        oneWayBondingCurve.purchase(oneWayBondingCurve.BAL_AMOUNT_CAP());
        vm.stopPrank();

        uint256 initialUsdcBalance = USDC.balanceOf(AaveV2Ethereum.COLLECTOR);
        uint256 initialUsdcAllowance = USDC.allowance(AaveV2Ethereum.COLLECTOR, address(oneWayBondingCurve));
        uint256 usdcAmount = (initialUsdcAllowance <= initialUsdcBalance) ? initialUsdcAllowance : initialUsdcBalance;
        uint256 initialAusdcBalance = AUSDC.balanceOf(AaveV2Ethereum.COLLECTOR);

        vm.expectEmit(true, true, false, true);
        emit Deposit(address(USDC), address(AUSDC), usdcAmount);
        oneWayBondingCurve.depositUsdcCollector();

        assertEq(USDC.balanceOf(AaveV2Ethereum.COLLECTOR), initialUsdcBalance - usdcAmount);
        assertGe(AUSDC.balanceOf(AaveV2Ethereum.COLLECTOR), initialAusdcBalance + usdcAmount);
    }

    function testDepositBalCollectorBalCapNotFilled() public {
        // Pass vote and execute proposal
        GovHelpers.passVoteAndExecute(vm, proposalId);

        uint256 amount = 90_000e18;

        vm.startPrank(BAL_WHALE);
        BAL.approve(address(oneWayBondingCurve), amount);
        oneWayBondingCurve.purchase(amount);
        vm.stopPrank();

        vm.expectRevert(OneWayBondingCurve.BalCapNotFilled.selector);
        oneWayBondingCurve.depositBalCollector();
    }

    function testDepositBalCollectorZeroAllowance() public {
        // Pass vote and execute proposal
        GovHelpers.passVoteAndExecute(vm, proposalId);

        // Filling out 100k BAL CAP
        vm.startPrank(BAL_WHALE);
        BAL.approve(address(oneWayBondingCurve), oneWayBondingCurve.BAL_AMOUNT_CAP());
        oneWayBondingCurve.purchase(oneWayBondingCurve.BAL_AMOUNT_CAP());
        vm.stopPrank();

        // Depositing all remaining BAL in Collector to make allowance 0
        oneWayBondingCurve.depositBalCollector();

        // Trying Deposit again
        vm.expectRevert(OneWayBondingCurve.ZeroAllowance.selector);
        oneWayBondingCurve.depositBalCollector();
    }

    function testDepositBalCollectorZeroBalance() public {
        // Pass vote and execute proposal
        GovHelpers.passVoteAndExecute(vm, proposalId);

        // Filling out 100k BAL CAP
        vm.startPrank(BAL_WHALE);
        BAL.approve(address(oneWayBondingCurve), oneWayBondingCurve.BAL_AMOUNT_CAP());
        oneWayBondingCurve.purchase(oneWayBondingCurve.BAL_AMOUNT_CAP());
        vm.stopPrank();

        // Transferring out remaining BAL in Collector
        vm.startPrank(AaveV2Ethereum.COLLECTOR);
        BAL.transfer(address(this), BAL.balanceOf(AaveV2Ethereum.COLLECTOR));

        vm.expectRevert(OneWayBondingCurve.ZeroBalance.selector);
        oneWayBondingCurve.depositBalCollector();
    }

    function testDepositBalCollector() public {
        // Pass vote and execute proposal
        GovHelpers.passVoteAndExecute(vm, proposalId);

        // Filling out 100k BAL CAP
        vm.startPrank(BAL_WHALE);
        BAL.approve(address(oneWayBondingCurve), oneWayBondingCurve.BAL_AMOUNT_CAP());
        oneWayBondingCurve.purchase(oneWayBondingCurve.BAL_AMOUNT_CAP());
        vm.stopPrank();

        uint256 initialBalBalance = BAL.balanceOf(AaveV2Ethereum.COLLECTOR);
        uint256 initialBalAllowance = BAL.allowance(AaveV2Ethereum.COLLECTOR, address(oneWayBondingCurve));
        uint256 balAmount = (initialBalAllowance <= initialBalBalance) ? initialBalAllowance : initialBalBalance;

        uint256 initialAbalBalance = ABAL.balanceOf(AaveV2Ethereum.COLLECTOR);

        vm.expectEmit(true, true, false, true);
        emit Deposit(address(BAL), address(ABAL), balAmount);
        oneWayBondingCurve.depositBalCollector();

        assertEq(BAL.balanceOf(AaveV2Ethereum.COLLECTOR), initialBalBalance - balAmount);
        assertGe(ABAL.balanceOf(AaveV2Ethereum.COLLECTOR), initialAbalBalance + balAmount);
    }

    function testSendEthtoBondingCurve() public {
        // Testing that you can't send ETH to the contract directly since not payable
        vm.startPrank(ETH_WHALE);
        (bool success, ) = address(oneWayBondingCurve).call{value: 1 ether}("");
        assertTrue(!success);
    }

    function testRescueTokens() public {
        assertEq(BAL.balanceOf(address(oneWayBondingCurve)), 0);
        assertEq(USDC.balanceOf(address(oneWayBondingCurve)), 0);

        uint256 balAmount = 10_000e18;
        uint256 usdcAmount = 10_000e6;

        vm.startPrank(BAL_WHALE);
        BAL.transfer(address(oneWayBondingCurve), balAmount);
        vm.stopPrank();

        vm.startPrank(USDC_WHALE);
        USDC.transfer(address(oneWayBondingCurve), usdcAmount);
        vm.stopPrank();

        assertEq(BAL.balanceOf(address(oneWayBondingCurve)), balAmount);
        assertEq(USDC.balanceOf(address(oneWayBondingCurve)), usdcAmount);

        uint256 initialCollectorBalBalance = BAL.balanceOf(AaveV2Ethereum.COLLECTOR);
        uint256 initialCollectorUsdcBalance = USDC.balanceOf(AaveV2Ethereum.COLLECTOR);

        address[] memory tokens = new address[](2);
        tokens[0] = address(BAL);
        tokens[1] = address(USDC);
        oneWayBondingCurve.rescueTokens(tokens);

        assertEq(BAL.balanceOf(AaveV2Ethereum.COLLECTOR), initialCollectorBalBalance + balAmount);
        assertEq(USDC.balanceOf(AaveV2Ethereum.COLLECTOR), initialCollectorUsdcBalance + usdcAmount);
        assertEq(BAL.balanceOf(address(oneWayBondingCurve)), 0);
        assertEq(USDC.balanceOf(address(oneWayBondingCurve)), 0);
    }

    function testOraclePriceZeroAmount() public {
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

    function testOraclePriceNegativeAmount() public {
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

    /*****************************************
     *   POST PROPOSAL EXECUTION FUZZ TESTS  *
     *****************************************/

    function testPurchaseFuzz(uint256 amount) public {
        // Pass vote and execute proposal
        GovHelpers.passVoteAndExecute(vm, proposalId);

        // Assuming upper bound of purchase of 100k BAL and lower bound of 0.000001 BAL
        vm.assume(amount >= 1e12 && amount <= oneWayBondingCurve.BAL_AMOUNT_CAP());

        vm.startPrank(BAL_WHALE);
        BAL.approve(address(oneWayBondingCurve), amount);

        uint256 initialCollectorUsdcBalance = USDC.balanceOf(AaveV2Ethereum.COLLECTOR);
        uint256 initialCollectorBalBalance = BAL.balanceOf(AaveV2Ethereum.COLLECTOR);
        uint256 initialPurchaserUsdcBalance = USDC.balanceOf(BAL_WHALE);
        uint256 initialPurchaserBalBalance = BAL.balanceOf(BAL_WHALE);

        assertEq(oneWayBondingCurve.totalUsdcPurchased(), 0);
        assertEq(oneWayBondingCurve.totalBalReceived(), 0);

        uint256 usdcAmountOut = oneWayBondingCurve.purchase(amount);

        assertEq(USDC.balanceOf(AaveV2Ethereum.COLLECTOR), initialCollectorUsdcBalance - usdcAmountOut);
        assertEq(BAL.balanceOf(AaveV2Ethereum.COLLECTOR), initialCollectorBalBalance + amount);
        assertEq(USDC.balanceOf(BAL_WHALE), initialPurchaserUsdcBalance + usdcAmountOut);
        assertEq(BAL.balanceOf(BAL_WHALE), initialPurchaserBalBalance - amount);
        assertEq(oneWayBondingCurve.totalUsdcPurchased(), usdcAmountOut);
        assertEq(oneWayBondingCurve.totalBalReceived(), amount);
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
}
