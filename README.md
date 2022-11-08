# AAVE <> Balancer Bonding Curve

This repository contains the One Way Bonding Curve contract for crowdsourcing ~100,000 BAL tokens for Aave and the Proposal Payload for Aave Governance.

## Specification

The Proposal Payload does the following:

1. Approve the Bonding Curve contract to spend 800,000 aUSDC from the Aave V2 Collector.

The Bonding Curve contract has the following functions and public storage variables:

1. `function purchase(uint256 amountIn, bool toUnderlying) external returns (uint256)`: This function allows the trader to purchase aUSDC/USDC for BAL, with the trader receiving a 50 bps reward over the BAL/USD Chainlink oracle price. It takes ` uint256 amountIn` (BAL amount input including 18 decimals) and `bool toUnderlying` (Whether to receive as USDC (true) or aUSDC (false)) as input parameters and returns the amount of aUSDC/USDC (including 6 decimals) received on purchase.

2. `function availableBalToBeFilled() public view returns (uint256)`: This getter/view function returns how close to the 100k BAL amount cap the bonding curve contract is at. Trader check this function before calling `purchase()` to see the amount of BAL left to be filled in the bonding curve contract. This should give the trader information on upto how much BAL they can put in the `amountIn` input parameter of the `purchase()` function.

3. `function getAmountOut(uint256 amountIn) public view returns (uint256)` : This getter/view function returns the amount of aUSDC/USDC that will be received after a bonding curve purchase using given BAL amount input (including the 50 bps reward over the BAL/USD Chainlink oracle price). Trader check this function before calling `purchase()` to see the amount of aUSDC/USDC you'll get for given BAL amount input.

4. `function getOraclePrice() public view returns (uint256)` : This getter/view function returns the current peg price of the referenced Chainlink BAL/USD oracle as USD per BAL (value includes 8 decimals).

5. `function rescueTokens(address[] calldata tokens) external` : This is a rescue function that can be called by anyone to transfer any tokens accidentally sent to the bonding curve contract to Aave V2 Collector. It takes an input list of token contract addresses.

6. `uint256 public totalAusdcPurchased` : Cumulative aUSDC/USDC purchased through the bonding curve contract.

7. `uint256 public totalBalReceived`: Cumulative BAL received through the bonding curve contract.

## Installation

It requires [Foundry](https://github.com/gakonst/foundry) installed to run. You can find instructions here [Foundry installation](https://github.com/gakonst/foundry#installation).

To set up the project manually, run the following commands:

```sh
$ git clone https://github.com/llama-community/aave-bal-bonding-curve.git
$ cd aave-bal-bonding-curve/
$ npm install
$ forge install
```

## Setup

Duplicate `.env.example` and rename to `.env`:

- Add a valid mainnet URL for an Ethereum JSON-RPC client for the `RPC_MAINNET_URL` variable.
- Add a valid Private Key for the `PRIVATE_KEY` variable.
- Add a valid Etherscan API Key for the `ETHERSCAN_API_KEY` variable.

### Commands

- `make build` - build the project
- `make test [optional](V={1,2,3,4,5})` - run tests (with different debug levels if provided)
- `make match MATCH=<TEST_FUNCTION_NAME> [optional](V=<{1,2,3,4,5}>)` - run matched tests (with different debug levels if provided)

### Deploy and Verify

- `make deploy-contracts` - deploy and verify contracts on mainnet
- `make deploy-proposal`- deploy proposal on mainnet

To confirm the deploy was successful, re-run your test suite but use the newly created contract address.
