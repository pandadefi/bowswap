import pytest
import itertools
import requests

from brownie import config
from brownie import Contract

CRV_META_3USD_VAULT = [
    "0xC4dAf3b5e2A9e93861c3FBDd25f1e943B8D87417",
    "0x8cc94ccd0f3841a468184aCA3Cc478D2148E1757",
    "0x5fA5B62c8AF877CB37031e0a3B2f34A78e3C56A6",
    "0x30FCf7c6cDfC46eC237783D94Fc78553E79d4E9C",
    "0xf8768814b88281DE4F532a3beEfA5b85B69b9324",
    "0x054AF22E1519b020516D72D749221c24756385C9",
    "0x3B96d491f067912D18563d56858Ba7d6EC67a6fa",
    "0x6Ede7F19df5df6EF23bD5B9CeDb651580Bdf56Ca",
]

CRV_META_BTC_VAULT = [
    "0x8fA3A9ecd9EFb07A8CE90A6eb014CF3c0E3B32Ef",
    "0xe9Dc63083c464d6EDcCFf23444fF3CFc6886f6FB",
    "0x3c5DF3077BcF800640B5DAE8c91106575a4826E6",
]

ALL_PAIRS = list(itertools.combinations(CRV_META_BTC_VAULT, 2)) + list(
    itertools.combinations(CRV_META_3USD_VAULT, 2)
)


WHALES = {
    "0xC4dAf3b5e2A9e93861c3FBDd25f1e943B8D87417": "0x80b41c3e3d5d23ab027837ea9e2d8a91bda9067c",
    "0x8cc94ccd0f3841a468184aCA3Cc478D2148E1757": "0x3841ef91d7e7af21cd2b6017a43f906a99b52bde",
    "0x5fA5B62c8AF877CB37031e0a3B2f34A78e3C56A6": "0x53b1aeaa018da00b4f458cc13d40eb3e8d1b85d6",
    "0x30FCf7c6cDfC46eC237783D94Fc78553E79d4E9C": "0x53aefe126dabafe7754c23e9953bf51fcc4d3d8f",
    "0xf8768814b88281DE4F532a3beEfA5b85B69b9324": "0x310d4fb2845c3e0c3c57165198d65a5327a373ea",
    "0x054AF22E1519b020516D72D749221c24756385C9": "0xfeb4acf3df3cdea7399794d0869ef76a6efaff52",
    "0x3B96d491f067912D18563d56858Ba7d6EC67a6fa": "0x99fd1378ca799ed6772fe7bcdc9b30b389518962",
    "0x6Ede7F19df5df6EF23bD5B9CeDb651580Bdf56Ca": "0x3b29c6e356f9445b693abb5df42fbc932062e0fb",
    "0x8fA3A9ecd9EFb07A8CE90A6eb014CF3c0E3B32Ef": "0xe6b108d4e5262f9f5aeb79e7b551940e2009e956",
    "0xe9Dc63083c464d6EDcCFf23444fF3CFc6886f6FB": "0x99fd1378ca799ed6772fe7bcdc9b30b389518962",
    "0x3c5DF3077BcF800640B5DAE8c91106575a4826E6": "0x99fd1378ca799ed6772fe7bcdc9b30b389518962",
}


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


@pytest.fixture
def whale(vault_from):
    yield WHALES[vault_from.address]


@pytest.fixture
def amount(vault_from):
    if "USD" in vault_from.name():
        yield 1000 * 10 ** vault_from.decimals()  # 1000 USD
    else:
        yield 0.1 * 10 ** vault_from.decimals()  # 0.1 BTC


@pytest.fixture
def vault_swapper(gov, VaultSwapper):
    yield gov.deploy(VaultSwapper)


@pytest.fixture(scope="function", autouse=True)
def shared_setup(fn_isolation):
    pass
