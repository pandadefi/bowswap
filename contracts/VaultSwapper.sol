// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

interface Vault is IERC20 {
    function decimals() external view returns (uint256);
    function deposit() external returns (uint256);
    function deposit(uint256 amount) external returns (uint256);
    function deposit(uint256 amount, address recipient) external returns (uint256);
    function withdraw() external returns (uint256);
    function withdraw(uint256 maxShares) external returns (uint256);
    function withdraw(uint256 maxShares, address recipient) external returns (uint256);
    function token() external view returns (address);
    function pricePerShare() external view returns (uint256);
    function totalAssets() external view returns (uint256);
    function availableDepositLimit() external view returns (uint256);
    function permit(
        address owner,
        address spender,
        uint256 amount,
        uint256 expiry,
        bytes calldata signature
    ) external returns (bool);
}

interface StableSwap {
    function remove_liquidity_one_coin(uint256 amount, int128 i, uint256 min_amount) external;
    function remove_liquidity_one_coin(uint256 amount, uint256 i, uint256 min_amount) external;

    function add_liquidity(uint256[2] calldata amounts, uint256 min_mint_amount) external;
    function add_liquidity(uint256[3] calldata amounts, uint256 min_mint_amount) external;
    function add_liquidity(uint256[4] calldata amounts, uint256 min_mint_amount) external;

    function calc_withdraw_one_coin(uint256 _token_amount, int128 i) external view returns (uint256);
    function calc_withdraw_one_coin(uint256 _token_amount, uint256 i) external view returns (uint256);

    function calc_token_amount(uint256[2] calldata amounts, bool is_deposit) external view returns (uint256);
    function calc_token_amount(uint256[2] calldata amounts) external view returns (uint256);
    function calc_token_amount(uint256[3] calldata amounts, bool is_deposit) external view returns (uint256);
    function calc_token_amount(uint256[3] calldata amounts) external view returns (uint256);
    function calc_token_amount(uint256[4] calldata amounts, bool is_deposit) external view returns (uint256);
    function calc_token_amount(uint256[4] calldata amounts) external view returns (uint256);

    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external;
    function exchange(uint256 i, uint256 j, uint256 dx, uint256 min_dy, bool useEth) external;

    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256);
    function get_dy(uint256 i, uint256 j, uint256 dx) external view returns (uint256);
}

interface Registry {
    function get_pool_from_lp_token(address lp) external view returns (address);
    function get_lp_token(address pool) external view returns (address);
    function get_n_coins(address) external view returns (uint256[2] memory);
    function get_coins(address) external view returns (address[8] memory);
}

interface FactoryRegistry {
    function get_coins(address) external view returns (address[4] memory);
    function get_n_coins(address) external view returns (uint256);
}

contract VaultSwapper is Initializable {
    Registry constant registry = Registry(0x90E00ACe148ca3b23Ac1bC8C240C2a7Dd9c2d7f5);
    FactoryRegistry constant factory_registry = FactoryRegistry(0xB9fC157394Af804a3578134A6585C0dc9cc990d4);

    uint256 private constant MIN_AMOUNT_OUT = 1;
    uint256 private constant MAX_DONATION = 10_000;
    uint256 private constant DEFAULT_DONATION = 30;
    uint256 private constant UNKNOWN_ORIGIN = 0;
    address private constant TRI_CRYPTO_POOL = 0x80466c64868E1ab14a1Ddf27A676C3fcBE638Fe5;
    address public owner;
    mapping(address => uint256) public num_coins;

    event Orgin(uint256 origin);

    enum Action {
        Deposit, Withdraw, Swap
    }

    struct Swap {
        Action action;
        address pool;
        uint128 n;
        uint128 m;
    }

    function initialize(address _owner) public initializer {
        owner = _owner;
    }

    function set_owner(address new_owner) public {
        require(owner == msg.sender);
        require(new_owner != address(0));
        owner = new_owner;
    }

    /**********************************************************************************************
    **  @notice Swap with approval using eip-2612, from a same metapool.
    **  @param from_vault The vault tokens should be taken from
    **  @param to_vault The vault tokens should be deposited to
    **  @param amount The amount of tokens you whish to use from the from_vault
    **  @param min_amount_out The minimal amount of tokens you would expect from the to_vault
    **  @param expiry signature expiry
    **  @param signature signature
    **********************************************************************************************/
    function metapool_swap_with_signature(
        address from_vault,
        address to_vault,
        uint256 amount,
        uint256 min_amount_out,
        uint256 expiry,
        bytes calldata signature
    ) public {
        metapool_swap_with_signature(
            from_vault,
            to_vault,
            amount,
            min_amount_out,
            expiry,
            signature,
            DEFAULT_DONATION,
            UNKNOWN_ORIGIN
        );
    }

    /**********************************************************************************************
    **  @notice Swap with approval using eip-2612, from a same metapool. Overloaded with two
    **      extra params.
    **  @param from_vault The vault tokens should be taken from
    **  @param to_vault The vault tokens should be deposited to
    **  @param amount The amount of tokens you whish to use from the from_vault
    **  @param min_amount_out The minimal amount of tokens you would expect from the to_vault
    **  @param expiry signature expiry
    **  @param signature signature
    **  @param donation amount of donation to give to Bowswap
    **  @param origin tracking for partnership
    **********************************************************************************************/
    function metapool_swap_with_signature(
        address from_vault,
        address to_vault,
        uint256 amount,
        uint256 min_amount_out,
        uint256 expiry,
        bytes calldata signature,
        uint256 donation,
        uint256 origin
    ) public {
        assert(
            Vault(from_vault).permit(
                msg.sender,
                address(this),
                amount,
                expiry,
                signature
            )
        );
        metapool_swap(
            from_vault,
            to_vault,
            amount,
            min_amount_out,
            donation,
            origin
        );
    }

    /**********************************************************************************************
    **  @notice swap tokens from one meta pool vault to an other
    **  @dev Remove funds from a vault, move one side of the asset from one curve pool to an other
    **  and  deposit into the new vault.
    **  @param from_vault The vault tokens should be taken from
    **  @param to_vault The vault tokens should be deposited to
    **  @param amount The amount of tokens you whish to use from the from_vault
    **  @param min_amount_out The minimal amount of tokens you would expect from the to_vault
    **********************************************************************************************/
    function metapool_swap(
        address from_vault,
        address to_vault,
        uint256 amount,
        uint256 min_amount_out
    ) public {
        metapool_swap(
            from_vault,
            to_vault,
            amount,
            min_amount_out,
            DEFAULT_DONATION,
            UNKNOWN_ORIGIN
        );
    }

    /**********************************************************************************************
    **  @notice swap tokens from one meta pool vault to an other. Overloaded with two extra params.
    **  @dev Remove funds from a vault, move one side of the asset from one curve pool to an other
    **  and  deposit into the new vault.
    **  @param from_vault The vault tokens should be taken from
    **  @param to_vault The vault tokens should be deposited to
    **  @param amount The amount of tokens you whish to use from the from_vault
    **  @param min_amount_out The minimal amount of tokens you would expect from the to_vault
    **  @param donation amount of donation to give to Bowswap
    **  @param origin tracking for partnership
    **********************************************************************************************/
    function metapool_swap(
        address from_vault,
        address to_vault,
        uint256 amount,
        uint256 min_amount_out,
        uint256 donation,
        uint256 origin
    ) public {
        address underlying = Vault(from_vault).token();
        address target = Vault(to_vault).token();

        address underlying_pool = _get_pool_from_lp_token(underlying);
        address target_pool = _get_pool_from_lp_token(target);

        Vault(from_vault).transferFrom(msg.sender, address(this), amount);
        uint256 underlying_amount = Vault(from_vault).withdraw(
            amount,
            address(this)
        );
        _remove_liquidity_one_coin(underlying_pool, underlying_amount, 1, 1);

        IERC20 underlying_coin = IERC20(_get_coin(underlying_pool, 1));
        uint256 liquidity_amount = underlying_coin.balanceOf(address(this));

        underlying_coin.approve(target_pool, liquidity_amount);

        StableSwap(target_pool).add_liquidity(
            [0, liquidity_amount],
            MIN_AMOUNT_OUT
        );

        uint256 target_amount = IERC20(target).balanceOf(address(this));
        if (donation != 0) {
            uint256 donating = (target_amount * donation) / MAX_DONATION;
            SafeERC20.safeTransfer(IERC20(target), owner, donating);
            target_amount -= donating;
        }

        approve(target, to_vault, target_amount);

        uint256 out = Vault(to_vault).deposit(target_amount, msg.sender);

        require(out >= min_amount_out, "out too low");
        if (origin != UNKNOWN_ORIGIN) {
            emit Orgin(origin);
        }
    }

    /**********************************************************************************************
    **  @notice estimate the amount of tokens out
    **  @param from_vault The vault tokens should be taken from
    **  @param to_vault The vault tokens should be deposited to
    **  @param amount The amount of tokens you whish to use from the from_vault
    **  @param donation amount of donation to give to Bowswap
    **  @return the amount of token shared expected in the to_vault
    **********************************************************************************************/
    function metapool_estimate_out(
        address from_vault,
        address to_vault,
        uint256 amount,
        uint256 donation
    ) public view returns (uint256) {
        address underlying = Vault(from_vault).token();
        address target = Vault(to_vault).token();

        address underlying_pool = _get_pool_from_lp_token(underlying);
        address target_pool = _get_pool_from_lp_token(target);

        uint256 pricePerShareFrom = Vault(from_vault).pricePerShare();
        uint256 pricePerShareTo = Vault(to_vault).pricePerShare();

        uint256 amount_out = (pricePerShareFrom * amount) / (10**Vault(from_vault).decimals());

        amount_out = _calc_withdraw_one_coin(underlying_pool, amount_out, 1);
        amount_out = StableSwap(target_pool).calc_token_amount([0, amount_out], true);
        amount_out -= (amount_out * donation) / MAX_DONATION;
        return (amount_out * (10**Vault(to_vault).decimals())) / pricePerShareTo;
    }

    /**********************************************************************************************
    **  @notice Swap with approval using eip-2612.
    **  @param from_vault The vault tokens should be taken from
    **  @param to_vault The vault tokens should be deposited to
    **  @param amount The amount of tokens you whish to use from the from_vault
    **  @param min_amount_out The minimal amount of tokens you would expect from the to_vault
    **  @param instructions list of instruction/path to follow to be able to get the desired amount
    **      out.
    **  @param signature signature
    **********************************************************************************************/
    function swap_with_signature(
        address from_vault,
        address to_vault,
        uint256 amount,
        uint256 min_amount_out,
        Swap[] calldata instructions,
        uint256 expiry,
        bytes calldata signature
    ) public {
        swap_with_signature(
            from_vault,
            to_vault,
            amount,
            min_amount_out,
            instructions,
            expiry,
            signature,
            DEFAULT_DONATION,
            UNKNOWN_ORIGIN
        );
    }

    /**********************************************************************************************
    **  @notice Swap with approval using eip-2612. Overloaded with two extra params.
    **  @param from_vault The vault tokens should be taken from
    **  @param to_vault The vault tokens should be deposited to
    **  @param amount The amount of tokens you whish to use from the from_vault
    **  @param min_amount_out The minimal amount of tokens you would expect from the to_vault
    **  @param instructions list of instruction/path to follow to be able to get the desired amount
    **      out.
    **  @param signature signature
    **  @param donation amount of donation to give to Bowswap
    **  @param origin tracking for partnership
    **********************************************************************************************/
    function swap_with_signature(
        address from_vault,
        address to_vault,
        uint256 amount,
        uint256 min_amount_out,
        Swap[] calldata instructions,
        uint256 expiry,
        bytes calldata signature,
        uint256 donation,
        uint256 origin
    ) public {
        assert(
            Vault(from_vault).permit(
                msg.sender,
                address(this),
                amount,
                expiry,
                signature
            )
        );
        swap(
            from_vault,
            to_vault,
            amount,
            min_amount_out,
            instructions,
            donation,
            origin
        );
    }

    /**********************************************************************************************
    **  @notice Swap tokens from one vault to an other via a Curve pools path.
    **  @param from_vault The vault tokens should be taken from
    **  @param to_vault The vault tokens should be deposited to
    **  @param amount The amount of tokens you whish to use from the from_vault
    **  @param min_amount_out The minimal amount of tokens you would expect from the to_vault
    **  @param instructions list of instruction/path to follow to be able to get the desired amount
    **      out.
    **  @param signature signature
    **********************************************************************************************/
    function swap(
        address from_vault,
        address to_vault,
        uint256 amount,
        uint256 min_amount_out,
        Swap[] calldata instructions
    ) public {
        swap(
            from_vault,
            to_vault,
            amount,
            min_amount_out,
            instructions,
            DEFAULT_DONATION,
            UNKNOWN_ORIGIN
        );
    }

    /**********************************************************************************************
    **  @notice Swap tokens from one vault to an other via a Curve pools path. Overloaded with
    **      two extra params.
    **  @param from_vault The vault tokens should be taken from
    **  @param to_vault The vault tokens should be deposited to
    **  @param amount The amount of tokens you whish to use from the from_vault
    **  @param min_amount_out The minimal amount of tokens you would expect from the to_vault
    **  @param instructions list of instruction/path to follow to be able to get the desired amount
    **      out.
    **  @param signature signature
    **  @param donation amount of donation to give to Bowswap
    **  @param origin tracking for partnership
    **********************************************************************************************/
    function swap(
        address from_vault,
        address to_vault,
        uint256 amount,
        uint256 min_amount_out,
        Swap[] calldata instructions,
        uint256 donation,
        uint256 origin
    ) public {
        address token = Vault(from_vault).token();
        address target = Vault(to_vault).token();

        Vault(from_vault).transferFrom(msg.sender, address(this), amount);
        amount = Vault(from_vault).withdraw(amount, address(this));

        uint256 n_coins;
        for (uint256 i = 0; i < instructions.length; i++) {
            if (instructions[i].action == Action.Deposit) {
                n_coins = _get_n_coins(instructions[i].pool);
                uint256[] memory list = new uint256[](n_coins);
                list[instructions[i].n] = amount;
                approve(token, instructions[i].pool, amount);

                if (n_coins == 2) {
                    StableSwap(instructions[i].pool).add_liquidity(
                        [list[0], list[1]],
                        1
                    );
                } else if (n_coins == 3) {
                    StableSwap(instructions[i].pool).add_liquidity(
                        [list[0], list[1], list[2]],
                        1
                    );
                } else if (n_coins == 4) {
                    StableSwap(instructions[i].pool).add_liquidity(
                        [list[0], list[1], list[2], list[3]],
                        1
                    );
                }

                token = _get_lp_token_from_pool(instructions[i].pool);
                amount = IERC20(token).balanceOf(address(this));
            } else if (instructions[i].action == Action.Withdraw) {
                token = _get_coin(instructions[i].pool, instructions[i].n);
                amount = remove_liquidity_one_coin(token, instructions[i].pool, amount, instructions[i].n);
            } else {
                approve(token, instructions[i].pool, amount);
                token = _get_coin(instructions[i].pool, instructions[i].m);
                amount = exchange(
                    token,
                    instructions[i].pool,
                    amount,
                    instructions[i].n,
                    instructions[i].m
                );
            }
        }

        require(target == token, "!path");

        if (donation != 0) {
            uint256 donating = (amount * donation) / MAX_DONATION;
            SafeERC20.safeTransfer(IERC20(target), owner, donating);
            amount -= donating;
        }
        approve(target, to_vault, amount);
        require(Vault(to_vault).availableDepositLimit() >= amount, "!depositLimit");
        uint256 out = Vault(to_vault).deposit(amount, msg.sender);

        require(out >= min_amount_out, "out too low");
        if (origin != UNKNOWN_ORIGIN) {
            emit Orgin(origin);
        }
    }

    /**********************************************************************************************
    **  @notice estimate the amount of tokens out for a standard swap
    **  @param from_vault The vault tokens should be taken from
    **  @param to_vault The vault tokens should be deposited to
    **  @param amount The amount of tokens you whish to use from the from_vault
    **  @param instructions list of instruction/path to follow to be able to get the desired amount
    **  @param donation amount of donation to give to Bowswap
    **  @return the amount of token shared expected in the to_vault
    **********************************************************************************************/
    function estimate_out(
        address from_vault,
        address to_vault,
        uint256 amount,
        Swap[] calldata instructions,
        uint256 donation
    ) public view returns (uint256) {
        uint256 pricePerShareFrom = Vault(from_vault).pricePerShare();
        uint256 pricePerShareTo = Vault(to_vault).pricePerShare();
        amount =
            (amount * pricePerShareFrom) /
            (10**Vault(from_vault).decimals());
        for (uint256 i = 0; i < instructions.length; i++) {
            uint256 n_coins = _get_view_n_coins(instructions[i].pool);
            if (instructions[i].action == Action.Deposit) {
                n_coins = _get_view_n_coins(instructions[i].pool);
                uint256[] memory list = new uint256[](n_coins);
                list[instructions[i].n] = amount;

                if (n_coins == 2) {
                    try
                        StableSwap(instructions[i].pool).calc_token_amount(
                            [list[0], list[1]],
                            true
                        )
                    returns (uint256 _amount) {
                        amount = _amount;
                    } catch {
                        amount = StableSwap(instructions[i].pool)
                            .calc_token_amount([list[0], list[1]]);
                    }
                } else if (n_coins == 3) {
                    try
                        StableSwap(instructions[i].pool).calc_token_amount(
                            [list[0], list[1], list[2]],
                            true
                        )
                    returns (uint256 _amount) {
                        amount = _amount;
                    } catch {
                        amount = StableSwap(instructions[i].pool)
                            .calc_token_amount([list[0], list[1], list[2]]);
                    }
                } else if (n_coins == 4) {
                    try
                        StableSwap(instructions[i].pool).calc_token_amount(
                            [list[0], list[1], list[2], list[3]],
                            true
                        )
                    returns (uint256 _amount) {
                        amount = _amount;
                    } catch {
                        amount = StableSwap(instructions[i].pool)
                            .calc_token_amount(
                                [list[0], list[1], list[2], list[3]]
                            );
                    }
                }
            } else if (instructions[i].action == Action.Withdraw) {
                amount = _calc_withdraw_one_coin(
                    instructions[i].pool,
                    amount,
                    instructions[i].n
                );
            } else {
                amount = _calc_exchange(instructions[i].pool,
                    amount,
                    instructions[i].n, instructions[i].m);
            }
        }
        amount -= (amount * donation) / MAX_DONATION;
        return (amount * (10**Vault(to_vault).decimals())) / pricePerShareTo;
    }

    /**********************************************************************************************
    **  @notice Safer approve that will check for allowance and reset approval before giving it.
    **  @param target erc20 to approve
    **  @param to_vault The operator
    **  @param amount The amount of tokens you whish to use from the target
    **********************************************************************************************/
    function approve(address target, address to_vault, uint256 amount) internal {
        uint256 allowance = IERC20(target).allowance(address(this), to_vault);
        if (allowance < amount) {
            if (allowance != 0) {
                SafeERC20.safeApprove(IERC20(target), to_vault, 0);
            }
            SafeERC20.safeApprove(IERC20(target), to_vault, type(uint256).max);
        }
    }

    /**********************************************************************************************
    **  @notice Wrapper around the pool function remove_liquidity_one_coin. This function does not
    **      have any return value, so we wrap a balanceOf before and after to get the updated
    **      amount.
    **  @dev Tricrypto pool does not have the same signature and should be handle differently.
    **  @param token Token that should be removed from pool
    **  @param pool Address of the curve pool to work with
    **  @param amount The amount of tokens we want to remove
    **  @param n Index in the coins of the pool to remove. pool.coins[n] should be equal to token
    **  @return the new amount of tokens available
    **********************************************************************************************/
    function remove_liquidity_one_coin(address token, address pool, uint256 amount, uint128 n) internal returns (uint256) {
        uint256 amountBefore = IERC20(token).balanceOf(address(this));
        if (pool == TRI_CRYPTO_POOL) {
            StableSwap(pool).remove_liquidity_one_coin(amount, uint256(n), min_amount);
        } else {
            StableSwap(pool).remove_liquidity_one_coin(amount, int128(n), min_amount);
        }
        uint256 newAmount = IERC20(token).balanceOf(address(this));
        require(newAmount > amountBefore, "!remove");
        return newAmount;
    }

    /**********************************************************************************************
    **  @notice Wrapper around the pool function exchange. This function does not have any return
    **      value, so we wrap a balanceOf before and after to get the updated amount.
    **  @dev Tricrypto pool does not have the same signature and should be handle differently.
    **  @param token Token that should be removed from pool
    **  @param pool Address of the curve pool to work with
    **  @param amount The amount of tokens we want to swap
    **  @param n Index in the coins of the pool to swap as from.
    **  @param m Index in the coins of the pool to swap as to.
    **  @return the new amount of tokens available
    **********************************************************************************************/
    function exchange(address token, address pool, uint256 amount, uint128 n, uint128 m) internal returns (uint256) {
        uint256 amountBefore = IERC20(token).balanceOf(address(this));
        if (pool == TRI_CRYPTO_POOL) {
            StableSwap(pool).exchange(uint256(n), uint256(m), amount, 1, false);
        } else {
            StableSwap(pool).exchange(int128(n), int128(m), amount, 1);
        }
        uint256 newAmount = IERC20(token).balanceOf(address(this));
        require(newAmount > amountBefore, "!exchange");
        return newAmount;
    }

    /**********************************************************************************************
    **  @notice Wrapper around the pool function get_dy.
    **  @dev Tricrypto pool does not have the same signature and should be handle differently.
    **  @param lp Address of the curve LP token to work with
    **  @return the pool with the relevant function, or the LP address if the pool is the LP
    **********************************************************************************************/
    function _calc_exchange(address pool, uint256 amount, uint128 n, uint128 m) internal view returns (uint256) {
        if (pool == TRI_CRYPTO_POOL) {
            return StableSwap(pool).get_dy(uint256(n), uint256(m), amount);
        }
        return StableSwap(pool).get_dy(int128(n), int128(m), amount);
    }

    /**********************************************************************************************
    **  @notice Wrapper around the pool function calc_withdraw_one_coin.
    **  @dev Tricrypto pool does not have the same signature and should be handle differently.
    **  @param pool Address of the curve pool to work with
    **  @param amount The amount of tokens we want to swap
    **  @param n Index in the coins of the pool we want to withdraw.
    **  @return the expected amount withdrawn from the pool
    **********************************************************************************************/
    function _calc_withdraw_one_coin(address pool, uint256 amount, uint128 n) internal view returns (uint256) {
        if (pool == TRI_CRYPTO_POOL) {
            return StableSwap(pool).calc_withdraw_one_coin(amount, uint256(n));
        }
        return StableSwap(pool).calc_withdraw_one_coin(amount, int128(n));
    }

    /**********************************************************************************************
    **  @notice Wrapper around the pool function get_coin.
    **  @dev A pool can be registered either in the registry or in the factory registry, so we need
    **  to find in which it is used.
    **  @param pool Address of the curve pool to work with
    **  @param n Index in the coins we want to get.
    **  @return the address of the token at index n
    **********************************************************************************************/
    function _get_coin(address pool, uint256 n) internal view returns (address) {
        address token = registry.get_coins(pool)[n];
        if (token != address(0x0)) return token;
        return factory_registry.get_coins(pool)[n];
    }

    /**********************************************************************************************
    **  @notice Wrapper around the pool function get_pool_from_lp_token.
    **  @dev A pool can be registered either in the registry or in the factory registry, so we need
    **  to find in which it is used.
    **  @param lp Address of the curve LP token to work with
    **  @return the pool with the relevant function, or the LP address if the pool is the LP
    **********************************************************************************************/
    function _get_pool_from_lp_token(address lp) internal view returns (address) {
        address pool = registry.get_pool_from_lp_token(lp);
        if (pool == address(0x0))
            return lp;
        return pool;
    }

    /**********************************************************************************************
    **  @notice Wrapper around the pool function get_lp_token.
    **  @dev A pool can be registered either in the registry or in the factory registry, so we need
    **  to find in which it is used.
    **  @param pool Address of the curve Pool to work with
    **  @return the LP token address for this pool if available of the pool address as fallback
    **********************************************************************************************/
    function _get_lp_token_from_pool(address pool) internal view returns(address) {
        address token = registry.get_lp_token(pool);
        if (token != address(0x0)) return token;
        return pool;
    }

    /**********************************************************************************************
    **  @notice Function to get the number of coins in a specific pool.
    **  @dev We cannot count on get_n_coins for the factory_registry because some pools, with coin,
    **      have a 0 return value. We have a local `num_coins` mapping which is init by this
    **      function and is used if available. Otherwise we try to get and count the number of
    **      coins for a specific pool
    **  @param pool Address of the curve Pool to work with
    **  @return The number of coins in this pool
    **********************************************************************************************/
    function _get_n_coins(address pool) internal returns (uint256) {
        uint256 num = num_coins[pool];
        if (num != 0) return num;

        num = registry.get_n_coins(pool)[0];
        if (num != 0) {
            num_coins[pool] = num;
            return num;
        }

        address[4] memory coins = factory_registry.get_coins(pool);
        for (uint256 index = 0; index < coins.length; index++) {
            if (coins[index] != address(0)) {
                num++;
            }
        }
        num_coins[pool] = num;
        return num;
    }

    /**********************************************************************************************
    **  @notice Function to get the number of coins in a specific pool.
    **  @param pool Address of the curve Pool to work with
    **  @return The number of coins in this pool
    **********************************************************************************************/
    function _get_view_n_coins(address pool) internal view returns (uint256) {
        uint256 num = num_coins[pool];
        if (num != 0) return num;

        num = registry.get_n_coins(pool)[0];
        if (num != 0) return num;

        address[4] memory coins = factory_registry.get_coins(pool);
        for (uint256 index = 0; index < coins.length; index++) {
            if (coins[index] != address(0)) {
                num++;
            }
        }
        return num;
    }
}
