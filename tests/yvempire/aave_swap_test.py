import pytest
from brownie import Contract


def test_v1_swap(user, registry, usdt, ausdt, get_ausdt, yv_empire):
    amount = 1_000 * 10**6
    get_ausdt(user, amount)
    ausdt.approve(yv_empire, amount, {"from": user})
    estimate = yv_empire.estimate["tuple"]((1, ausdt, amount))
    yv_empire.migrate["tuple"]((1, ausdt, amount), {"from": user})
    vault = Contract(registry.latestVault(usdt))
    assert vault.balanceOf(user) != 0
    assert pytest.approx(vault.balanceOf(user)) == estimate


def test_v1_swap_many(user, registry, usdt, ausdt, get_ausdt, yv_empire):
    amount = 1_000 * 10**6
    get_ausdt(user, amount)
    ausdt.approve(yv_empire, amount, {"from": user})
    [estimate] = yv_empire.estimate["tuple[]"]([(1, ausdt, amount)])
    yv_empire.migrate["tuple[]"]([(1, ausdt, amount)], {"from": user})
    vault = Contract(registry.latestVault(usdt))
    assert vault.balanceOf(user) != 0
    assert pytest.approx(vault.balanceOf(user)) == estimate


def test_v2_swap(user, registry, usdc, ausdcv2, get_ausdcv2, yv_empire):
    amount = 1_000 * 10**6
    get_ausdcv2(user, amount)
    ausdcv2.approve(yv_empire, amount, {"from": user})
    estimate = yv_empire.estimate["tuple"]((2, ausdcv2, amount))
    yv_empire.migrate["tuple"]((2, ausdcv2, amount), {"from": user})
    vault = Contract(registry.latestVault(usdc))
    assert vault.balanceOf(user) != 0
    assert pytest.approx(vault.balanceOf(user)) == estimate


def test_v2_swap_many(user, registry, usdc, ausdcv2, get_ausdcv2, yv_empire):
    amount = 1_000 * 10**6
    get_ausdcv2(user, amount)
    ausdcv2.approve(yv_empire, amount, {"from": user})
    [estimate] = yv_empire.estimate["tuple[]"]([(2, ausdcv2, amount)])
    yv_empire.migrate["tuple[]"]([(2, ausdcv2, amount)], {"from": user})
    vault = Contract(registry.latestVault(usdc))
    assert vault.balanceOf(user) != 0
    assert pytest.approx(vault.balanceOf(user)) == estimate
