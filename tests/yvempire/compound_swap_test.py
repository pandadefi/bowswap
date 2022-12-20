import pytest
import brownie
from brownie import Contract


def test_swap(user, cusdc, get_cusdc, yv_empire):
    amount = 1_000 * 10**8
    get_cusdc(user, amount)
    cusdc.approve(yv_empire, amount, {"from": user})
    [estimate] = yv_empire.estimate["tuple[]"]([(0, cusdc, amount)])
    yv_empire.migrate["tuple[]"]([(0, cusdc, amount)], {"from": user})
    vault = Contract("0xa354F35829Ae975e850e23e9615b11Da1B3dC4DE")
    assert vault.balanceOf(user) != 0
    assert pytest.approx(vault.balanceOf(user)) == estimate
