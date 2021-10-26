import pytest
import brownie
from brownie import chain
from eth_account import Account


def transfer(token, amount, whale, to):
    token.transfer(to, amount, {"from": whale, "gas_price": 0})


def test_metapool_swap(user, vault_from, vault_to, whale, vault_swapper, amount, gov):
    transfer(vault_from, amount, whale, user)
    vault_from.approve(vault_swapper, amount, {"from": user})
    # gets a estimate of the amount out
    estimate = vault_swapper.metapool_estimate_out(vault_from, vault_to, amount)
    # Makes sure it revert if amout out is too small
    with brownie.reverts():
        vault_swapper.metapool_swap(
            vault_from, vault_to, amount, amount * 1.1, {"from": user}
        )

    # Do the swap
    vault_swapper.metapool_swap(
        vault_from, vault_to, amount, estimate * 0.99, {"from": user}
    )
    assert vault_to.balanceOf(user) > estimate * 0.99
    assert pytest.approx(
        vault_to.balanceOf(user) * (100 / 99.5) * 0.005, rel=10e-6
    ) == vault_to.balanceOf(gov)


def test_metapool_swap_no_donation(
    user, vault_from, vault_to, whale, vault_swapper, amount, gov
):
    transfer(vault_from, amount, whale, user)
    vault_from.approve(vault_swapper, amount, {"from": user})
    # gets a estimate of the amount out
    estimate = vault_swapper.metapool_estimate_out(vault_from, vault_to, amount)
    # Makes sure it revert if amout out is too small
    with brownie.reverts():
        vault_swapper.metapool_swap(
            vault_from, vault_to, amount, amount * 1.1, {"from": user}
        )

    # Do the swap
    vault_swapper.metapool_swap(
        vault_from, vault_to, amount, estimate * 0.99, 0, {"from": user}
    )
    assert vault_to.balanceOf(user) > estimate * 0.99
    assert vault_to.balanceOf(gov) == 0


def test_metapool_swap_large_donation(
    user, vault_from, vault_to, whale, vault_swapper, amount, gov
):
    transfer(vault_from, amount, whale, user)
    vault_from.approve(vault_swapper, amount, {"from": user})
    # gets a estimate of the amount out
    estimate = vault_swapper.metapool_estimate_out(vault_from, vault_to, amount)
    # Makes sure it revert if amout out is too small
    with brownie.reverts():
        vault_swapper.metapool_swap(
            vault_from, vault_to, amount, amount * 1.1, {"from": user}
        )

    # Do the swap
    vault_swapper.metapool_swap(
        vault_from, vault_to, amount, estimate * 0.99, 5000, {"from": user}
    )
    assert vault_to.balanceOf(user) > estimate * 0.499
    assert vault_to.balanceOf(gov) > estimate * 0.499


def test_metapool_swap_permit(
    vault_from, vault_to, whale, vault_swapper, amount, sign_vault_permit
):

    user = Account.create()
    transfer(vault_from, amount, whale, user.address)

    deadline = chain[-1].timestamp + 3600
    signature = sign_vault_permit(
        vault_from, user, str(vault_swapper), allowance=int(amount), deadline=deadline
    )
    estimate = vault_swapper.metapool_estimate_out(vault_from, vault_to, amount)

    vault_swapper.metapool_swap_with_signature(
        vault_from,
        vault_to,
        amount,
        estimate * 0.99,
        deadline,
        signature,
        {"from": user.address},
    )
    assert vault_to.balanceOf(user.address) > estimate * 0.999
