from brownie import CrvVaultSwapper, accounts, network, web3, Contract
from eth_utils import is_checksum_address

import click

TRANSFERS = [
    (
        "0xC4dAf3b5e2A9e93861c3FBDd25f1e943B8D87417",
        "0x6965292e29514e527df092659fb4638dc39e7248",
        1000 * 10 ** 18,
    ),
    (
        "0xe9dc63083c464d6edccff23444ff3cfc6886f6fb",
        "0x99fd1378ca799ed6772fe7bcdc9b30b389518962",
        0.2 * 10 ** 18,
    ),
]


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
    swapper = dev.deploy(CrvVaultSwapper)
    print("CrvVaultSwapper deployed at:" + str(swapper))

    to = get_address("send seed funds to")
    dev.transfer(to, 1 * 10 ** 18)
    for (vault, whale, amount) in TRANSFERS:
        token = Contract(vault)
        token.transfer(to, amount, {"from": whale})
