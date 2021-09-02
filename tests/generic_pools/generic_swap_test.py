import pytest
import brownie
from brownie import chain
from eth_account import Account


def transfer(token, amount, whale, to):
    token.transfer(to, amount, {"from": whale, "gas_price": 0})


def test_generic_swap(
    user, vault_from, vault_to, whale, vault_swapper, amount, instructions
):
    transfer(vault_from, amount, whale, user)
    vault_from.approve(vault_swapper, amount, {"from": user})
    estimate = vault_swapper.estimate_out(vault_from, vault_to, amount, instructions)
    vault_swapper.swap(vault_from, vault_to, amount, 1, instructions, {"from": user})

    assert vault_to.balanceOf(user) > estimate * 0.999


def test_generic_swap_permit(
    vault_from, vault_to, whale, vault_swapper, amount, instructions, sign_vault_permit
):

    user = Account.create()
    transfer(vault_from, amount, whale, user.address)

    deadline = chain[-1].timestamp + 3600
    signature = sign_vault_permit(
        vault_from, user, str(vault_swapper), allowance=int(amount), deadline=deadline
    )
    estimate = vault_swapper.estimate_out(vault_from, vault_to, amount, instructions)

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
