def main():
    click.echo(f"You are using the '{network.show_active()}' network")
    dev = accounts.load(
        click.prompt(
            "Which account should I seed funds too", type=click.Choice(accounts.load())
        )
    )
