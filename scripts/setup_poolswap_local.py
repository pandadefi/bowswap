from brownie import VaultSwapper, accounts, network, web3, Contract
from eth_utils import is_checksum_address
import requests
import time
import click

TRANSFERS = [
    (
        "0xC4dAf3b5e2A9e93861c3FBDd25f1e943B8D87417",
        1000 * 10 ** 18,
    ),
    (
        "0xe9dc63083c464d6edccff23444ff3cfc6886f6fb",
        0.2 * 10 ** 18,
    ),
    (
        "0x7Da96a3891Add058AdA2E826306D812C638D87a7",
        1000 * 10 ** 6,
    ),
    (
        "0xA696a63cc78DfFa1a63E9E50587C197387FF6C7E",
        0.2 * 10 ** 8,
    ),
    (
        "0x84E13785B5a27879921D6F685f041421C7F482dA",
        0.2 * 10 ** 18,
    ),
    (
        "0xf2db9a7c0ACd427A680D640F02d90f6186E71725",
        200 * 10 ** 18,
    ),
]


def get_whale(vault: str) -> str:
    url = "https://api.ethplorer.io/getTopTokenHolders/" + vault + "?apiKey=freekey"
    resp = requests.get(url, allow_redirects=True)
    return resp.json()["holders"][0]["address"]


def get_address(msg: str, default: str = None) -> str:
    val = click.prompt(msg, default=default)

    # Keep asking user for click.prompt until it passes
    while True:

        if is_checksum_address(val):
            return val
        elif addr := web3.ens.address(val):
            click.echo(f"Found ENS '{val}' [{addr}]")
            return addr

        click.echo(
            f"I'm sorry, but '{val}' is not a checksummed address or valid ENS record"
        )
        # NOTE: Only display default once
        val = click.prompt(msg)


def main():
    click.echo(f"You are using the '{network.show_active()}' network")
    dev = accounts[0]
    swapper = dev.deploy(VaultSwapper)
    print("VaultSwapper deployed at:" + str(swapper))

    to = get_address("send seed funds to")
    dev.transfer(to, 1 * 10 ** 18)
    for (vault, amount) in TRANSFERS:
        token = Contract(vault)
        token.transfer(to, amount, {"from": get_whale(vault)})
        time.sleep(0.5)  # API rate limit
