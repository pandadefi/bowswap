# @version 0.2.14
"""
@title Yearn Vault Swapper
@license GNU AGPLv3
@author yearn.finance
@notice
  Yearn vault swapper should be used to swap from one crv vault to an other.
"""

from vyper.interfaces import ERC20
N_ALL_COINS: constant(int128) = 2


interface Vault:
    def token() -> address: view
    def apiVersion() -> String[28]: view
    def governance() -> address: view
    def withdraw(
    maxShares: uint256,
    recipient: address
    ) -> uint256: nonpayable
    def deposit(amount: uint256, recipient: address) -> uint256: nonpayable
    def pricePerShare() -> uint256: view
    def transferFrom(f: address, to: address, amount: uint256) -> uint256: nonpayable
    def decimals() -> uint256: view

interface StableSwap:
    def remove_liquidity_one_coin(amount: uint256, i: int128, min_amount: uint256): nonpayable
    def coins(i: uint256) -> address: view
    def add_liquidity(amounts: uint256[N_ALL_COINS], min_mint_amount: uint256): nonpayable
    def calc_withdraw_one_coin(_token_amount: uint256, i: int128) -> uint256: view
    def calc_token_amount(amounts: uint256[N_ALL_COINS], is_deposit: bool) -> uint256: view

interface Token:
    def minter() -> address: view

pools: public(HashMap[address, address])
management: public(address)

@external
def __init__():
    self.management = msg.sender
    self.pools[0x7Eb40E450b9655f4B3cC4259BCC731c63ff55ae6] = 0x42d7025938bEc20B69cBae5A77421082407f053A
    self.pools[0x64eda51d3Ad40D56b9dFc5554E06F94e1Dd786Fd] = 0xC25099792E9349C7DD09759744ea681C7de2cb66
    self.pools[0x1AEf73d49Dedc4b1778d0706583995958Dc862e6] = 0x8474DdbE98F5aA3179B3B3F5942D724aFcdec9f6
    self.pools[0x97E2768e8E73511cA874545DC5Ff8067eB19B787] = 0x3E01dD8a5E1fb3481F0F589056b428Fc308AF0Fb
    self.pools[0x3E01dD8a5E1fb3481F0F589056b428Fc308AF0Fb] = 0x3E01dD8a5E1fb3481F0F589056b428Fc308AF0Fb
    self.pools[0xEd279fDD11cA84bEef15AF5D39BB4d4bEE23F0cA] = 0xEd279fDD11cA84bEef15AF5D39BB4d4bEE23F0cA
    self.pools[0xEcd5e75AFb02eFa118AF914515D6521aaBd189F1] = 0xEcd5e75AFb02eFa118AF914515D6521aaBd189F1
    self.pools[0x5B5CFE992AdAC0C9D48E05854B2d91C73a003858] = 0x3eF6A01A0f81D6046290f3e2A8c5b843e738E604
    self.pools[0x4f3E8F405CF5aFC05D68142F3783bDfE13811522] = 0x0f9cb53Ebe405d49A0bbdBD291A65Ff571bC83e1
    self.pools[0x4807862AA8b2bF68830e4C8dc86D0e9A998e085a] = 0x4807862AA8b2bF68830e4C8dc86D0e9A998e085a

@external
def swap(from_vault: address, to_vault: address, amount: uint256, min_amount_out: uint256):
    underlying: address = Vault(from_vault).token()
    target: address = Vault(to_vault).token()

    underlying_pool: address = self.pools[underlying]
    if underlying_pool == ZERO_ADDRESS:
        underlying_pool= Token(underlying).minter()

    target_pool: address = self.pools[target]
    if target_pool == ZERO_ADDRESS:
        target_pool= Token(target).minter()

    Vault(from_vault).transferFrom(msg.sender, self, amount)

    underlying_amount: uint256 = Vault(from_vault).withdraw(amount, self)
    
    StableSwap(underlying_pool).remove_liquidity_one_coin(underlying_amount, 1, 1)
    
    liquidity_amount: uint256 = ERC20(StableSwap(underlying_pool).coins(1)).balanceOf(self)
    ERC20(StableSwap(underlying_pool).coins(1)).approve(target_pool, liquidity_amount)

    StableSwap(target_pool).add_liquidity([0, liquidity_amount], 1)

    target_amount: uint256 = ERC20(target).balanceOf(self)
    if ERC20(target).allowance(self, to_vault) < target_amount:
        ERC20(target).approve(to_vault, 0)
        ERC20(target).approve(to_vault, MAX_UINT256) 

    out:uint256 = Vault(to_vault).deposit(target_amount, msg.sender)
    assert(out >= min_amount_out)

@view
@external
def estimate_out(from_vault: address, to_vault: address, amount: uint256) -> uint256:
    underlying: address = Vault(from_vault).token()
    target: address = Vault(to_vault).token()

    underlying_pool: address = self.pools[underlying]
    if underlying_pool == ZERO_ADDRESS:
        underlying_pool= Token(underlying).minter()

    target_pool: address = self.pools[target]
    if target_pool == ZERO_ADDRESS:
        target_pool= Token(target).minter()

    pricePerShareFrom: uint256 = Vault(from_vault).pricePerShare()
    pricePerShareTo: uint256 = Vault(to_vault).pricePerShare()

    amount_out: uint256 = pricePerShareFrom * amount / (10 ** Vault(from_vault).decimals())
    amount_out = StableSwap(underlying_pool).calc_withdraw_one_coin(amount_out, 1)
    amount_out = StableSwap(target_pool).calc_token_amount([0, amount_out], True)
    
    return amount_out * (10 ** Vault(to_vault).decimals()) / pricePerShareTo

@external
def setMinter(token: address, pool: address):
    assert(msg.sender == self.management)
    self.pools[token] = pool
