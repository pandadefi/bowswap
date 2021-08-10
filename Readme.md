# bowswap.finance

Swap between crv-metapool vaults.
[bowswap.finance](https://bowswap.finance)

## Getting started

### Requirements

- Python 3.8 or above
- ganache-cli

### Setup

```
pip install -r requirements-dev.txt
```

In order to work on this project you need to set the following enviroment variables:

```
ETHERSCAN_TOKEN=
WEB3_INFURA_PROJECT_ID=
```

- ETHERSCAN_TOKEN can be created with an etherscan account [here](https://etherscan.io/myapikey)
- WEB3_INFURA_PROJECT_ID can be created with a infur account [here](https://infura.io/dashboard/ethereum)

## Running test

```
brownie test
```

## Running the project on local fork

On a first shell tab run:

```
ganache-cli --port 8545 --gasLimit 12000000 --accounts 10 --hardfork istanbul --mnemonic brownie --fork $WEB3_INFURA_PROJECT_ID --chainId 1
```

On a second shell tab:

```
brownie run scripts/setup_local_env.py
```

This command will deploy the contract, ask for wallet address (you can use metamask connected to localhost:8545) to seed with ETH and yCRV tokens.

The address should have recieved one ETH and ycrv tokens for the following vaults:

- 0xC4dAf3b5e2A9e93861c3FBDd25f1e943B8D87417 (Curve USDP Pool yVault)
- 0x3c5DF3077BcF800640B5DAE8c91106575a4826E6 (Curve pBTC Pool yVault)


## UI

Frontend can be found on https://github.com/TBouder/bowswap_ui
