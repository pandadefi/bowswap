// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface Vault is IERC20 {
    function decimals() external view returns (uint256);

    function deposit() external returns (uint256);

    function deposit(uint256 amount) external returns (uint256);

    function deposit(uint256 amount, address recipient)
        external
        returns (uint256);

    function withdraw() external returns (uint256);

    function withdraw(uint256 maxShares) external returns (uint256);

    function withdraw(uint256 maxShares, address recipient)
        external
        returns (uint256);

    function token() external view returns (address);

    function pricePerShare() external view returns (uint256);

    function totalAssets() external view returns (uint256);
}

interface StableSwap {
    function remove_liquidity_one_coin(
        uint256 amount,
        int128 i,
        uint256 min_amount
    ) external;

    function coins(uint256 i) external view returns (address);

    function add_liquidity(uint256[2] calldata amounts, uint256 min_mint_amount)
        external;

    function calc_withdraw_one_coin(uint256 _token_amount, int128 i)
        external
        view
        returns (uint256);

    function calc_token_amount(uint256[2] calldata amounts, bool is_deposit)
        external
        view
        returns (uint256);
}

interface Registry {
    function get_pool_from_lp_token(address lp) external view returns (address);
}

contract CrvVaultSwapper {
    Registry registry = Registry(0x90E00ACe148ca3b23Ac1bC8C240C2a7Dd9c2d7f5);

    /**
        @notice swap tokens from one vault to an other
        @dev Remove funds from a vault, move one side of 
        the asset from one curve pool to an other and 
        deposit into the new vault.
        @param from_vault The vault tokens should be taken from
        @param to_vault The vault tokens should be deposited to
        @param amount The amount of tokens you whish to use from the from_vault
        @param min_amount_out The minimal amount of tokens you would expect from the to_vault
    */
    function swap(
        address from_vault,
        address to_vault,
        uint256 amount,
        uint256 min_amount_out
    ) public {
        address underlying = Vault(from_vault).token();
        address target = Vault(to_vault).token();

        address underlying_pool = registry.get_pool_from_lp_token(underlying);
        address target_pool = registry.get_pool_from_lp_token(target);

        Vault(from_vault).transferFrom(msg.sender, address(this), amount);
        uint256 underlying_amount = Vault(from_vault).withdraw(
            amount,
            address(this)
        );
        StableSwap(underlying_pool).remove_liquidity_one_coin(
            underlying_amount,
            1,
            1
        );
        uint256 liquidity_amount = IERC20(StableSwap(underlying_pool).coins(1))
            .balanceOf(address(this));
        IERC20(StableSwap(underlying_pool).coins(1)).approve(
            target_pool,
            liquidity_amount
        );

        StableSwap(target_pool).add_liquidity([0, liquidity_amount], 1);

        uint256 target_amount = IERC20(target).balanceOf(address(this));
        if (IERC20(target).allowance(address(this), to_vault) < target_amount) {
            SafeERC20.safeApprove(IERC20(target), to_vault, 0);
            SafeERC20.safeApprove(IERC20(target), to_vault, type(uint256).max);
        }
        uint256 out = Vault(to_vault).deposit(target_amount, msg.sender);
        require(out >= min_amount_out);
    }

    /**
        @notice estimate the amount of tokens out
        @param from_vault The vault tokens should be taken from
        @param to_vault The vault tokens should be deposited to
        @param amount The amount of tokens you whish to use from the from_vault
        @return the amount of token shared expected in the to_vault
     */
    function estimate_out(
        address from_vault,
        address to_vault,
        uint256 amount
    ) public view returns (uint256) {
        address underlying = Vault(from_vault).token();
        address target = Vault(to_vault).token();

        address underlying_pool = registry.get_pool_from_lp_token(underlying);
        address target_pool = registry.get_pool_from_lp_token(target);

        uint256 pricePerShareFrom = Vault(from_vault).pricePerShare();
        uint256 pricePerShareTo = Vault(to_vault).pricePerShare();

        uint256 amount_out = (pricePerShareFrom * amount) /
            (10**Vault(from_vault).decimals());
        amount_out = StableSwap(underlying_pool).calc_withdraw_one_coin(
            amount_out,
            1
        );
        amount_out = StableSwap(target_pool).calc_token_amount(
            [0, amount_out],
            true
        );

        return
            (amount_out * (10**Vault(to_vault).decimals())) / pricePerShareTo;
    }
}
