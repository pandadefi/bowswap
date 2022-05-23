import pytest
from eth_account import Account

from ape import Contract, chain
from web3 import Web3
from eth_account.messages import encode_structured_data


def chain_id():
    # BUG: hardhat provides mismatching chain.id and chainid()
    # https://github.com/trufflesuite/ganache/issues/1643
    return 1 if web3.clientVersion.startswith("HardhatNetwork") else chain.id


@pytest.fixture
def sign_vault_permit():
    def sign_vault_permit(
        vault: Contract,
        owner: Account,  # NOTE: Must be a eth_key account, not Brownie
        spender: str,
        allowance: int = 2**256 - 1,  # Allowance to set with `permit`
        deadline: int = 0,  # 0 means no time limit
        override_nonce: int = None,
    ):
        name = "Yearn Vault"
        version = vault.apiVersion()
        if override_nonce:
            nonce = override_nonce
        else:
            nonce = vault.nonces(owner.address)
        data = {
            "types": {
                "EIP712Domain": [
                    {"name": "name", "type": "string"},
                    {"name": "version", "type": "string"},
                    {"name": "chainId", "type": "uint256"},
                    {"name": "verifyingContract", "type": "address"},
                ],
                "Permit": [
                    {"name": "owner", "type": "address"},
                    {"name": "spender", "type": "address"},
                    {"name": "value", "type": "uint256"},
                    {"name": "nonce", "type": "uint256"},
                    {"name": "deadline", "type": "uint256"},
                ],
            },
            "domain": {
                "name": name,
                "version": version,
                "chainId": chain_id(),
                "verifyingContract": str(vault),
            },
            "primaryType": "Permit",
            "message": {
                "owner": owner.address,
                "spender": spender,
                "value": allowance,
                "nonce": nonce,
                "deadline": deadline,
            },
        }
        permit = encode_structured_data(data)
        return owner.sign_message(permit).signature

    return sign_vault_permit
