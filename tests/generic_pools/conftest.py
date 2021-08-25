import pytest
import itertools
import requests

from brownie import Contract

ALL_PAIRS = [
    [
        "0xC4dAf3b5e2A9e93861c3FBDd25f1e943B8D87417",
        "0x84E13785B5a27879921D6F685f041421C7F482dA",
        [(False, "0x42d7025938bEc20B69cBae5A77421082407f053A", 1)],
    ],  # META to 3CRV
    [
        "0x84E13785B5a27879921D6F685f041421C7F482dA",
        "0xC4dAf3b5e2A9e93861c3FBDd25f1e943B8D87417",
        [(True, "0x42d7025938bEc20B69cBae5A77421082407f053A", 1)],
    ],  # 3CRV to META
    [
        "0x5f18C75AbDAe578b483E5F43f12a39cF75b973a9",
        "0xC4dAf3b5e2A9e93861c3FBDd25f1e943B8D87417",
        [
            (True, "0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7", 1),
            (True, "0x42d7025938bEc20B69cBae5A77421082407f053A", 1),
        ],
    ],  # USDC vault to cuve vault
    [
        "0xC4dAf3b5e2A9e93861c3FBDd25f1e943B8D87417",
        "0x5f18C75AbDAe578b483E5F43f12a39cF75b973a9",
        [
            (False, "0x42d7025938bEc20B69cBae5A77421082407f053A", 1),
            (False, "0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7", 1),
        ],
    ],  # cuve vault to USDC vault
    [
        "0xC4dAf3b5e2A9e93861c3FBDd25f1e943B8D87417",
        "0x3D980E50508CFd41a13837A60149927a11c03731",
        [
            (False, "0x42d7025938bEc20B69cBae5A77421082407f053A", 1),
            (False, "0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7", 2),
            (True, "0x80466c64868E1ab14a1Ddf27A676C3fcBE638Fe5", 0),
        ],
    ],  # USDP crv to tricrv
    [
        "0xA74d4B67b3368E83797a35382AFB776bAAE4F5C8",
        "0x8414Db07a7F743dEbaFb402070AB01a4E0d2E45e",
        [
            [False, "0x43b4FdFD4Ff969587185cDB6f0BD875c5Fc83f8c", 1],
            [False, "0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7", 2],
            [True, "0x80466c64868E1ab14a1Ddf27A676C3fcBE638Fe5", 0],
            [False, "0x80466c64868E1ab14a1Ddf27A676C3fcBE638Fe5", 1],
            [True, "0x7fC77b5c7614E1533320Ea6DDc2Eb61fa00A9714", 1],
        ],
    ],  # alUSD crv to sBTC
]


@pytest.fixture
def gov(accounts):
    yield accounts[0]


@pytest.fixture
def user(accounts):
    yield accounts[1]


@pytest.fixture(params=ALL_PAIRS)
def vaults(request):
    yield request.param


@pytest.fixture()
def vault_from(vaults):
    yield Contract(vaults[0])


@pytest.fixture()
def vault_to(vaults):
    yield Contract(vaults[1])


@pytest.fixture()
def instructions(vaults):
    yield vaults[2]


@pytest.fixture
def whale(vault_from):
    url = (
        "https://api.ethplorer.io/getTopTokenHolders/"
        + vault_from.address
        + "?apiKey=freekey"
    )
    resp = requests.get(url, allow_redirects=True)
    yield resp.json()["holders"][0]["address"]


@pytest.fixture
def amount(vault_from):
    if (
        vault_from.address
        in [
            "0x1C6a9783F812b3Af3aBbf7de64c3cD7CC7D1af44",
            "0x6Ede7F19df5df6EF23bD5B9CeDb651580Bdf56Ca",
        ]
        or "USD" in vault_from.name()
    ):
        yield 1000 * 10 ** vault_from.decimals()  # 1000 USD
    else:
        yield 0.1 * 10 ** vault_from.decimals()  # 0.1 BTC


@pytest.fixture
def vault_swapper(gov, VaultSwapper):
    yield gov.deploy(VaultSwapper)


@pytest.fixture(scope="function", autouse=True)
def shared_setup(fn_isolation):
    pass
