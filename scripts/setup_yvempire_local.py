from brownie import YVEmpire, accounts, network, web3, Contract
from eth_utils import is_checksum_address

import click

AAVE_V1_WHALE = "0x9e6bf04486CD9039D3e3d57fb01633dff13A9a5c"
AAVE_V2_WHALE = "0x3DdfA8eC3052539b6C9549F12cEA2C295cfF5296"
COMP_WHALE = "0xe1eD4DA4284924dDAf69983B4D813FB1be58c380"

TRANSFERS = [
    (
        "0xbcca60bb61934080951369a648fb03df4f96263c",  # aUSDC v2
        AAVE_V2_WHALE,
        1000 * 10**6,
    ),
    (
        "0x3ed3b47dd13ec9a98b44e6204a523e766b225811",  # aUSDT v2
        AAVE_V2_WHALE,
        1000 * 10**6,
    ),
    (
        "0x030ba81f1c18d280636f32af80b9aad02cf0854e",  # aWETH v2
        AAVE_V2_WHALE,
        2 * 10**18,
    ),
    (
        "0x71fc860F7D3A592A4a98740e39dB31d25db65ae8",  # aUSDT v1
        AAVE_V1_WHALE,
        1000 * 10**6,
    ),
    (
        "0xfC1E690f61EFd961294b3e1Ce3313fBD8aa4f85d",  # aDAI v1
        AAVE_V1_WHALE,
        1000 * 10**18,
    ),
    (
        "0x39aa39c021dfbae8fac545936693ac917d5e7563",  # cUSDC
        COMP_WHALE,
        1000 * 10**18,
    ),
    (
        "0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5",  # cETH
        COMP_WHALE,
        2 * 10**8,
    ),
    (
        "0xf650c3d88d12db855b8bf7d11be6c55a4e07dcc9",  # cUSDT
        COMP_WHALE,
        1000 * 10**8,
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
    swapper = dev.deploy(YVEmpire)
    print("YVEmpire deployed at:" + str(swapper))

    to = get_address("send seed funds to")
    dev.transfer(to, 1 * 10**18)
    for (vault, whale, amount) in TRANSFERS:
        token = Contract(vault)
        token.transfer(to, amount, {"from": whale})
