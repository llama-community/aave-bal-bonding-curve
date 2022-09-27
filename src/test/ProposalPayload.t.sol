// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

// testing libraries
import "@forge-std/Test.sol";

// contract dependencies
import {IAaveGovernanceV2} from "../external/aave/IAaveGovernanceV2.sol";
import {ProposalPayload} from "../ProposalPayload.sol";
import {OneWayBondingCurve} from "../OneWayBondingCurve.sol";
import {DeployMainnetProposal} from "../../script/DeployMainnetProposal.s.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

contract ProposalPayloadTest is Test {
    address public constant usdcTokenAddress = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant ausdcTokenAddress = 0xBcca60bB61934080951369a648Fb03DF4F96263C;
    uint256 public constant usdcAmount = 603000e6;
    uint256 public constant ausdcAmount = 250000e6;

    address public constant aaveMainnetReserveFactor = 0x464C71f6c2F760DdA6093dCB91C24c39e5d6e18c;

    IAaveGovernanceV2 private aaveGovernanceV2 = IAaveGovernanceV2(0xEC568fffba86c094cf06b22134B23074DFE2252c);

    address[] private aaveWhales;

    address private proposalPayloadAddress;

    uint256 private proposalId;

    OneWayBondingCurve public oneWayBondingCurve;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 15227480);
        // aave whales may need to be updated based on the block being used
        // these are sometimes exchange accounts or whale who move their funds

        // select large holders here: https://etherscan.io/token/0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9#balances
        aaveWhales.push(0xBE0eB53F46cd790Cd13851d5EFf43D12404d33E8);
        aaveWhales.push(0x26a78D5b6d7a7acEEDD1e6eE3229b372A624d8b7);
        aaveWhales.push(0x2FAF487A4414Fe77e2327F0bf4AE2a264a776AD2);

        // Deploying One Way Bonding Curve
        oneWayBondingCurve = new OneWayBondingCurve(usdcAmount);

        // create proposal is configured to deploy a Payload contract and call execute() as a delegatecall
        // most proposals can use this format - you likely will not have to update this
        _createProposal();

        // these are generic steps for all proposals - no updates required
        _voteOnProposal();
        _skipVotingPeriod();
        _queueProposal();
        _skipQueuePeriod();

        vm.label(address(oneWayBondingCurve), "OneWayBondingCurve");
        vm.label(proposalPayloadAddress, "ProposalPayload");
    }

    function testSetup() public {
        IAaveGovernanceV2.ProposalWithoutVotes memory proposal = aaveGovernanceV2.getProposalById(proposalId);
        assertEq(proposalPayloadAddress, proposal.targets[0], "TARGET_IS_NOT_PAYLOAD");

        IAaveGovernanceV2.ProposalState state = aaveGovernanceV2.getProposalState(proposalId);
        assertEq(uint256(state), uint256(IAaveGovernanceV2.ProposalState.Queued), "PROPOSAL_NOT_IN_EXPECTED_STATE");
    }

    function testExecute() public {
        uint256 initialAaveMainnetReserveFactorAusdcBalance = IERC20(ausdcTokenAddress).balanceOf(
            aaveMainnetReserveFactor
        );
        uint256 initialAaveMainnetReserveFactorUsdcBalance = IERC20(usdcTokenAddress).balanceOf(
            aaveMainnetReserveFactor
        );

        assertEq(IERC20(usdcTokenAddress).balanceOf(proposalPayloadAddress), 0);
        assertEq(IERC20(ausdcTokenAddress).balanceOf(proposalPayloadAddress), 0);
        assertEq(IERC20(usdcTokenAddress).allowance(aaveMainnetReserveFactor, address(oneWayBondingCurve)), 0);

        _executeProposal();

        // AAVE Mainnet Reserve Factor gets some additional aTokens minted to it while redeeming
        // https://github.com/aave/protocol-v2/blob/baeb455fad42d3160d571bd8d3a795948b72dd85/contracts/protocol/libraries/logic/ReserveLogic.sol#L265-L325
        assertGe(
            IERC20(ausdcTokenAddress).balanceOf(aaveMainnetReserveFactor),
            initialAaveMainnetReserveFactorAusdcBalance - ausdcAmount
        );

        assertEq(
            IERC20(usdcTokenAddress).balanceOf(aaveMainnetReserveFactor),
            initialAaveMainnetReserveFactorUsdcBalance + ausdcAmount
        );
        assertEq(IERC20(usdcTokenAddress).balanceOf(proposalPayloadAddress), 0);
        assertEq(IERC20(ausdcTokenAddress).balanceOf(proposalPayloadAddress), 0);
        assertEq(IERC20(usdcTokenAddress).allowance(aaveMainnetReserveFactor, address(oneWayBondingCurve)), usdcAmount);
    }

    function _executeProposal() public {
        // execute proposal
        aaveGovernanceV2.execute(proposalId);

        // confirm state after
        IAaveGovernanceV2.ProposalState state = aaveGovernanceV2.getProposalState(proposalId);
        assertEq(uint256(state), uint256(IAaveGovernanceV2.ProposalState.Executed), "PROPOSAL_NOT_IN_EXPECTED_STATE");
    }

    /*******************************************************************************/
    /******************     Aave Gov Process - Create Proposal     *****************/
    /*******************************************************************************/

    function _createProposal() public {
        ProposalPayload proposalPayload = new ProposalPayload(oneWayBondingCurve, usdcAmount, ausdcAmount);
        proposalPayloadAddress = address(proposalPayload);

        vm.prank(aaveWhales[0]);
        proposalId = DeployMainnetProposal._deployMainnetProposal(
            proposalPayloadAddress,
            0x344d3181f08b3186228b93bac0005a3a961238164b8b06cbb5f0428a9180b8a7 // TODO: Replace with actual IPFS Hash
        );
    }

    /*******************************************************************************/
    /***************     Aave Gov Process - No Updates Required      ***************/
    /*******************************************************************************/

    function _voteOnProposal() public {
        IAaveGovernanceV2.ProposalWithoutVotes memory proposal = aaveGovernanceV2.getProposalById(proposalId);
        vm.roll(proposal.startBlock + 1);
        for (uint256 i; i < aaveWhales.length; i++) {
            vm.prank(aaveWhales[i]);
            aaveGovernanceV2.submitVote(proposalId, true);
        }
    }

    function _skipVotingPeriod() public {
        IAaveGovernanceV2.ProposalWithoutVotes memory proposal = aaveGovernanceV2.getProposalById(proposalId);
        vm.roll(proposal.endBlock + 1);
    }

    function _queueProposal() public {
        aaveGovernanceV2.queue(proposalId);
    }

    function _skipQueuePeriod() public {
        IAaveGovernanceV2.ProposalWithoutVotes memory proposal = aaveGovernanceV2.getProposalById(proposalId);
        vm.warp(proposal.executionTime + 1);
    }
}
