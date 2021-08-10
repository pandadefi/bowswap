import pytest
import brownie


def transfer(token, amount, whale, to):
    token.transfer(to, amount, {"from": whale})


def test_swap(user, vault_from, vault_to, whale, vault_swapper, amount):
    transfer(vault_from, amount, whale, user)
    vault_from.approve(vault_swapper, amount, {"from": user})
    # gets a estimate of the amount out
    estimate = vault_swapper.estimate_out(vault_from, vault_to, amount)
    # Makes sure it revert if amout out is too small
    with brownie.reverts():
        vault_swapper.swap(vault_from, vault_to, amount, amount * 1.1, {"from": user})

    # Do the swap
    vault_swapper.swap(vault_from, vault_to, amount, estimate * 0.999, {"from": user})
    assert vault_to.balanceOf(user) > estimate * 0.999
    print(vault_to.balanceOf(user))
