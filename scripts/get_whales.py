import requests
import time
import json

CRV_META_3USD_VAULT = [
    "0xC4dAf3b5e2A9e93861c3FBDd25f1e943B8D87417",
    "0x8cc94ccd0f3841a468184aCA3Cc478D2148E1757",
    "0xB4AdA607B9d6b2c9Ee07A275e9616B84AC560139",
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

ALL = CRV_META_3USD_VAULT + CRV_META_BTC_VAULT


def main():
    print("WHALES LIST:")
    for vault in CRV_META_3USD_VAULT + CRV_META_BTC_VAULT:
        url = "https://api.ethplorer.io/getTopTokenHolders/" + vault + "?apiKey=freekey"
        resp = requests.get(url, allow_redirects=True)
        print("'" + vault + "': '" + resp.json()["holders"][0]["address"] + "',")
        time.sleep(1.1)
    pass
