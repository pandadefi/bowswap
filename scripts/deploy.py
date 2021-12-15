from brownie import VaultSwapper, YVEmpire, Contract, accounts, network
import click


def main():
    click.echo(f"You are using the '{network.show_active()}' network")
    dev = accounts.load(click.prompt("Account", type=click.Choice(accounts.load())))
    click.echo(f"You are using: 'dev' [{dev.address}]")

    create2deployer = Contract("0x62349c8510de543e0bf77df87f548a1d5f642e7b")
    tx = create2deployer.deploy(
        VaultSwapper.bytecode,
        "0xcc531095a68a08c983ec900272d1ea2d4fa07525f14b01aece76ed000c000000",
        {"from": dev, "max_fee": "98 gwei", "priority_fee": "1 gwei"},
    )
    print(tx.events)
