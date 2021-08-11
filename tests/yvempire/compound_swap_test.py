import pytest
import brownie
from brownie import Contract


def test_swap(user, cusdc, get_cusdc, yv_empire):
    amount = 10_000 * 10 ** 8
    get_cusdc(user, amount)
    cusdc.approve(yv_empire, amount, {"from": user})
    yv_empire.migrate([(0, cusdc)], {"from": user})
    vault = Contract("0x5f18C75AbDAe578b483E5F43f12a39cF75b973a9")
    assert vault.balanceOf(user) != 0
