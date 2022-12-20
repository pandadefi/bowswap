import pytest

from brownie import config
from brownie import Contract


@pytest.fixture
def gov(accounts):
    yield accounts[0]


@pytest.fixture
def user(accounts):
    yield accounts[1]


@pytest.fixture()
def vaults(request):
    yield request.param


@pytest.fixture()
def registry():
    yield Contract("0x50c1a2eA0a861A967D9d0FFE2AE4012c2E053804")


@pytest.fixture
def yv_empire(gov, YVEmpire, registry):
    yield gov.deploy(
        YVEmpire,
        registry,
        "0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9",
        "0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9",
    )


@pytest.fixture()
def usdc():
    yield Contract("0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48")


@pytest.fixture()
def usdt():
    yield Contract("0xdac17f958d2ee523a2206206994597c13d831ec7")


@pytest.fixture()
def cusdc():
    yield Contract("0x39aa39c021dfbae8fac545936693ac917d5e7563")


@pytest.fixture()
def cusdc_whale():
    yield "0xabde2f02fe84e083e1920471b54c3612456365ef"


@pytest.fixture
def get_cusdc(cusdc, cusdc_whale):
    def get_cusdc(to, amount):
        cusdc.transfer(to, amount, {"from": cusdc_whale})
        assert cusdc.balanceOf(to) >= amount

    yield get_cusdc


@pytest.fixture()
def ausdcv2():
    yield Contract("0xBcca60bB61934080951369a648Fb03DF4F96263C")


@pytest.fixture()
def ausdcv2_whale():
    yield "0x3ddfa8ec3052539b6c9549f12cea2c295cff5296"


@pytest.fixture
def get_ausdcv2(ausdcv2, ausdcv2_whale):
    def get_ausdcv2(to, amount):
        ausdcv2.transfer(to, amount, {"from": ausdcv2_whale})
        assert ausdcv2.balanceOf(to) >= amount

    yield get_ausdcv2


@pytest.fixture()
def ausdt():
    yield Contract("0x71fc860F7D3A592A4a98740e39dB31d25db65ae8")


@pytest.fixture()
def ausdt_whale():
    yield "0x83f798e925bcd4017eb265844fddabb448f1707d"


@pytest.fixture
def get_ausdt(ausdt, ausdt_whale):
    def get_ausdt(to, amount):
        ausdt.transfer(to, amount, {"from": ausdt_whale})
        assert ausdt.balanceOf(to) >= amount

    yield get_ausdt


@pytest.fixture(scope="function", autouse=True)
def shared_setup(fn_isolation):
    pass
