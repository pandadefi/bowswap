import pytest
import brownie


def transfer(token, amount, whale, to):
    token.transfer(to, amount, {"from": whale})


def test_view(vault_swapper, vault_from, vault_to, amount):
    print("Estimate: " + vault_from.name() + " to " + vault_to.name())
    estimate = vault_swapper.estimate_out(vault_from, vault_to, amount)
    assert estimate > 0


def test_swap(user, vault_from, vault_to, whale, vault_swapper, amount):
    print("Testing transfer: ")
    transfer(vault_from, amount, whale, user)
    vault_from.approve(vault_swapper, amount, {"from": user})
    estimate = vault_swapper.estimate_out(vault_from, vault_to, amount)
    vault_swapper.swap(vault_from, vault_to, amount, estimate * 0.999, {"from": user})
    assert vault_to.balanceOf(user) > estimate * 0.999
    print(vault_to.balanceOf(user))


def test_swap_revert(user, vault_from, vault_to, whale, vault_swapper, amount):
    transfer(vault_from, amount, whale, user)
    vault_from.approve(vault_swapper, amount, {"from": user})
    with brownie.reverts():
        vault_swapper.swap(vault_from, vault_to, amount, amount * 1.1, {"from": user})


def test_set_pool(user, vault_from, gov, vault_swapper):
    with brownie.reverts():
        vault_swapper.setPool(vault_from, vault_from, {"from": user})
    vault_swapper.setPool(vault_from, vault_from, {"from": gov})
