import pytest
import brownie


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
