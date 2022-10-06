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

contract ProposalPayloadTest is Test {
    address public constant AAVE_WHALE = 0xBE0eB53F46cd790Cd13851d5EFf43D12404d33E8;

    uint256 public proposalId;

    address public constant usdcTokenAddress = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant ausdcTokenAddress = 0xBcca60bB61934080951369a648Fb03DF4F96263C;
    uint256 public constant ausdcAmount = 603000e6;

    address public immutable aaveMainnetReserveFactor = AaveV2Ethereum.COLLECTOR;

    OneWayBondingCurve public oneWayBondingCurve;
    ProposalPayload public proposalPayload;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 15690548);

        // Deploying One Way Bonding Curve
        oneWayBondingCurve = new OneWayBondingCurve(ausdcAmount);

        // Deploy Payload
        proposalPayload = new ProposalPayload(oneWayBondingCurve, ausdcAmount);

        // Create Proposal
        vm.prank(AAVE_WHALE);
        proposalId = DeployMainnetProposal._deployMainnetProposal(
            address(proposalPayload),
            0x344d3181f08b3186228b93bac0005a3a961238164b8b06cbb5f0428a9180b8a7 // TODO: Replace with actual IPFS Hash
        );

        vm.label(address(oneWayBondingCurve), "OneWayBondingCurve");
        vm.label(address(proposalPayload), "ProposalPayload");
    }

    function testExecute() public {
        uint256 initialAaveMainnetReserveFactorAusdcBalance = IERC20(ausdcTokenAddress).balanceOf(
            aaveMainnetReserveFactor
        );
        uint256 initialAaveMainnetReserveFactorUsdcBalance = IERC20(usdcTokenAddress).balanceOf(
            aaveMainnetReserveFactor
        );

        assertEq(IERC20(ausdcTokenAddress).balanceOf(address(proposalPayload)), 0);
        assertEq(IERC20(usdcTokenAddress).balanceOf(address(proposalPayload)), 0);
        assertEq(IERC20(ausdcTokenAddress).allowance(aaveMainnetReserveFactor, address(oneWayBondingCurve)), 0);
        assertEq(IERC20(usdcTokenAddress).allowance(aaveMainnetReserveFactor, address(oneWayBondingCurve)), 0);

        // Pass vote and execute proposal
        GovHelpers.passVoteAndExecute(vm, proposalId);

        // AAVE Mainnet Reserve Factor gets some additional aTokens minted to it while depositing/withdrawing
        // https://github.com/aave/protocol-v2/blob/baeb455fad42d3160d571bd8d3a795948b72dd85/contracts/protocol/libraries/logic/ReserveLogic.sol#L265-L325
        assertGe(
            IERC20(ausdcTokenAddress).balanceOf(aaveMainnetReserveFactor),
            initialAaveMainnetReserveFactorAusdcBalance + initialAaveMainnetReserveFactorUsdcBalance
        );
        assertEq(IERC20(usdcTokenAddress).balanceOf(aaveMainnetReserveFactor), 0);
        assertEq(IERC20(ausdcTokenAddress).balanceOf(address(proposalPayload)), 0);
        assertEq(IERC20(usdcTokenAddress).balanceOf(address(proposalPayload)), 0);
        assertEq(
            IERC20(ausdcTokenAddress).allowance(aaveMainnetReserveFactor, address(oneWayBondingCurve)),
            ausdcAmount
        );
        assertEq(IERC20(usdcTokenAddress).allowance(aaveMainnetReserveFactor, address(oneWayBondingCurve)), 0);
    }
}
