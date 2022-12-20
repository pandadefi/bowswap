import pytest
from brownie import Contract


def test_v1_swap(user, registry, usdt, ausdt, get_ausdt, yv_empire):
    amount = 1_000 * 10**6
    get_ausdt(user, amount)
    ausdt.approve(yv_empire, amount, {"from": user})
    yv_empire.migrate["tuple"]((1, ausdt), {"from": user})
    vault = Contract(registry.latestVault(usdt))
    assert vault.balanceOf(user) != 0


def test_v1_swap_many(user, registry, usdt, ausdt, get_ausdt, yv_empire):
    amount = 1_000 * 10**6
    get_ausdt(user, amount)
    ausdt.approve(yv_empire, amount, {"from": user})
    yv_empire.migrate["tuple[]"]([(1, ausdt)], {"from": user})
    vault = Contract(registry.latestVault(usdt))
    assert vault.balanceOf(user) != 0


def test_v2_swap(user, registry, usdc, ausdcv2, get_ausdcv2, yv_empire):
    amount = 1_000 * 10**6
    get_ausdcv2(user, amount)
    ausdcv2.approve(yv_empire, amount, {"from": user})
    yv_empire.migrate["tuple"]((2, ausdcv2), {"from": user})
    vault = Contract(registry.latestVault(usdc))
    assert vault.balanceOf(user) != 0


def test_v2_swap_many(user, registry, usdc, ausdcv2, get_ausdcv2, yv_empire):
    amount = 1_000 * 10**6
    get_ausdcv2(user, amount)
    ausdcv2.approve(yv_empire, amount, {"from": user})
    yv_empire.migrate["tuple[]"]([(2, ausdcv2)], {"from": user})
    vault = Contract(registry.latestVault(usdc))
    assert vault.balanceOf(user) != 0
