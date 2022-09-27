# AAVE <> Balancer Bonding Curve

This repository contains the One Way Bonding Curve contract for crowdsourcing ~100,000 BAL tokens for Aave and the Proposal Payload for Aave Governance.

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
