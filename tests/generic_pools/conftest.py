import pytest
import itertools
import requests

from brownie import Contract

ALL_PAIRS = [
    [
        "0xC4dAf3b5e2A9e93861c3FBDd25f1e943B8D87417", "0x84E13785B5a27879921D6F685f041421C7F482dA",
        [(1, "0x42d7025938bEc20B69cBae5A77421082407f053A", 1, 0)],
    ],  # META to 3CRV
    [
        "0x84E13785B5a27879921D6F685f041421C7F482dA",
        "0xC4dAf3b5e2A9e93861c3FBDd25f1e943B8D87417",
        [(0, "0x42d7025938bEc20B69cBae5A77421082407f053A", 1, 0)],
    ],  # 3CRV to META
    [
        "0xa354F35829Ae975e850e23e9615b11Da1B3dC4DE",
        "0xC4dAf3b5e2A9e93861c3FBDd25f1e943B8D87417",
        [
            (0, "0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7", 1, 0),
            (0, "0x42d7025938bEc20B69cBae5A77421082407f053A", 1, 0),
        ],
    ],  # USDC vault to cuve vault
    [
        "0xC4dAf3b5e2A9e93861c3FBDd25f1e943B8D87417",
        "0xa354F35829Ae975e850e23e9615b11Da1B3dC4DE",
        [
            (1, "0x42d7025938bEc20B69cBae5A77421082407f053A", 1, 0),
            (1, "0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7", 1, 0),
        ],
    ],
    [
        "0xf8768814b88281DE4F532a3beEfA5b85B69b9324", "0xd8C620991b8E626C099eAaB29B1E3eEa279763bb",
        [
            (1, "0xEcd5e75AFb02eFa118AF914515D6521aaBd189F1", 1, 0),
            (2, "0x890f4e345B1dAED0367A877a1612f86A1f86985f", 1, 0),
            (0, "0x55A8a39bc9694714E2874c1ce77aa1E599461E18", 1, 0)
	    ]
    ],
    [
        "0xA74d4B67b3368E83797a35382AFB776bAAE4F5C8",
        "0x8414Db07a7F743dEbaFb402070AB01a4E0d2E45e",
        [
            [1, "0x43b4FdFD4Ff969587185cDB6f0BD875c5Fc83f8c", 1, 0],
            [1, "0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7", 2, 0],
            [2, "0x80466c64868E1ab14a1Ddf27A676C3fcBE638Fe5", 0, 1],
            [0, "0x7fC77b5c7614E1533320Ea6DDc2Eb61fa00A9714", 1, 0],
        ],
    ],  # alUSD crv to sBTC
    [
        "0xf2db9a7c0ACd427A680D640F02d90f6186E71725",
        "0x671a912C10bba0CFA74Cfc2d6Fba9BA1ed9530B2",
        [[1, "0xF178C0b5Bb7e7aBF4e12A4838C7b7c5bA2C623c0", 0, 0]],
    ],  # crvLink to link
    [
        "0x67e019bfbd5a67207755D04467D6A70c0B75bF60",
        "0x25212Df29073FfFA7A67399AcEfC2dd75a831A1A",
        [
            [1, "0x19b080FE1ffA0553469D20Ca36219F17Fcf03859", 1, 0],
            [0, "0x0Ce6a5fF5217e38315f87032CF90686C96627CAA", 1, 0],
        ],
    ],  # ibEUR to EURS
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
    swapper = gov.deploy(VaultSwapper)
    swapper.initialize(gov)
    yield swapper


@pytest.fixture(scope="function", autouse=True)
def shared_setup(fn_isolation):
    pass
