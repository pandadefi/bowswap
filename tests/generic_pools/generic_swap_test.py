import pytest
import brownie
from brownie import chain, Contract
from eth_account import Account


def transfer(token, amount, whale, to):
    token.transfer(to, amount, {"from": whale, "gas_price": 0})


def test_generic_swap(
    user, vault_from, vault_to, whale, vault_swapper, amount, instructions, gov
):
    transfer(vault_from, amount, whale, user)
    vault_from.approve(vault_swapper, amount, {"from": user})
    estimate = vault_swapper.estimate_out(
        vault_from, vault_to, amount, instructions, 30
    )
    vault_swapper.swap(vault_from, vault_to, amount, 1, instructions, {"from": user})

    assert vault_to.balanceOf(user) > estimate * 0.999
    vault_underlying_token = Contract(vault_to.token())
    assert vault_underlying_token.balanceOf(gov) != 0


def test_generic_swap_no_donation(
    user, vault_from, vault_to, whale, vault_swapper, amount, instructions, gov
):
    transfer(vault_from, amount, whale, user)
    vault_from.approve(vault_swapper, amount, {"from": user})
    estimate = vault_swapper.estimate_out(vault_from, vault_to, amount, instructions, 0)
    vault_swapper.swap(
        vault_from, vault_to, amount, 1, instructions, 0, 0, {"from": user}
    )

    assert vault_to.balanceOf(user) > estimate * 0.999
    vault_underlying_token = Contract(vault_to.token())
    assert vault_underlying_token.balanceOf(gov) == 0


def test_generic_swap_large_donation(
    user, vault_from, vault_to, whale, vault_swapper, amount, instructions, gov
):
    transfer(vault_from, amount, whale, user)
    vault_from.approve(vault_swapper, amount, {"from": user})
    estimate = vault_swapper.estimate_out(
        vault_from, vault_to, amount, instructions, 5000
    )
    tx = vault_swapper.swap(
        vault_from, vault_to, amount, 1, instructions, 5000, 1, {"from": user}
    )
    assert tx.events["Orgin"]["origin"] == 1

    assert vault_to.balanceOf(user) > estimate * 0.999
    vault_underlying_token = Contract(vault_to.token())
    assert vault_underlying_token.balanceOf(gov) != 0


def test_generic_swap_permit(
    vault_from, vault_to, whale, vault_swapper, amount, instructions, sign_vault_permit
):

    user = Account.create()
    transfer(vault_from, amount, whale, user.address)

    deadline = chain[-1].timestamp + 3600
    signature = sign_vault_permit(
        vault_from, user, str(vault_swapper), allowance=int(amount), deadline=deadline
    )
    estimate = vault_swapper.estimate_out(
        vault_from, vault_to, amount, instructions, 30
    )

    vault_swapper.swap_with_signature(
        vault_from,
        vault_to,
        amount,
        1,
        instructions,
        deadline,
        signature,
        {"from": user.address},
    )
    assert vault_to.balanceOf(user.address) > estimate * 0.999
