// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IStableSwap.sol";
import "./interfaces/ICurveRegistry.sol";
import "./interfaces/ICurveFactoryRegistry.sol";

contract VaultSwapper is Initializable {
    ICurveRegistry private constant _REGISTRY =
        ICurveRegistry(0x90E00ACe148ca3b23Ac1bC8C240C2a7Dd9c2d7f5);
    ICurveFactoryRegistry private constant _FACTORY_REGISTRY =
        ICurveFactoryRegistry(0xB9fC157394Af804a3578134A6585C0dc9cc990d4);

    uint256 private constant _MIN_AMOUNT_OUT = 1;
    uint256 private constant _MAX_DONATION = 10_000;
    uint256 private constant _DEFAULT_DONATION = 30;
    uint256 private constant _UNKNOWN_ORIGIN = 0;
    address private constant _TRI_CRYPTO_POOL =
        0x80466c64868E1ab14a1Ddf27A676C3fcBE638Fe5;
    address public owner;
    mapping(address => uint256) public numCoins;

    event Orgin(uint256 origin);

    enum Action {
        Deposit,
        Withdraw,
        Swap
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

    function setOwner(address newOwner) public {
        require(owner == msg.sender, "!owner");
        require(newOwner != address(0), "!zero");
        owner = newOwner;
    }

    /**
        @notice Swap with approval using eip-2612
        @param fromVault The vault tokens should be taken from
        @param toVault The vault tokens should be deposited to
        @param amount The amount of tokens you whish to use from the fromVault
        @param minAmountOut The minimal amount of tokens you would expect from the toVault
        @param expiry signature expiry
        @param signature signature
    */
    function metapoolSwapWithSignature(
        address fromVault,
        address toVault,
        uint256 amount,
        uint256 minAmountOut,
        uint256 expiry,
        bytes calldata signature
    ) public {
        metapoolSwapWithSignature(
            fromVault,
            toVault,
            amount,
            minAmountOut,
            expiry,
            signature,
            _DEFAULT_DONATION,
            _UNKNOWN_ORIGIN
        );
    }

    /**
        @notice Swap with approval using eip-2612, from a same metapool. Overloaded with two extra params.
        @param fromVault The vault tokens should be taken from
        @param toVault The vault tokens should be deposited to
        @param amount The amount of tokens you whish to use from the fromVault
        @param minAmountOut The minimal amount of tokens you would expect from the toVault
        @param expiry signature expiry
        @param signature signature
        @param donation amount of donation to give to Bowswap
        @param origin tracking for partnership
    */
    function metapoolSwapWithSignature(
        address fromVault,
        address toVault,
        uint256 amount,
        uint256 minAmountOut,
        uint256 expiry,
        bytes calldata signature,
        uint256 donation,
        uint256 origin
    ) public {
        assert(
            IVault(fromVault).permit(
                msg.sender,
                address(this),
                amount,
                expiry,
                signature
            )
        );
        metapoolSwap(
            fromVault,
            toVault,
            amount,
            minAmountOut,
            donation,
            origin
        );
    }

    /**
        @notice swap tokens from one meta pool vault to an other
        @dev Remove funds from a vault, move one side of  the asset from one curve pool to an other and deposit into the new vault.
        @param fromVault The vault tokens should be taken from
        @param toVault The vault tokens should be deposited to
        @param amount The amount of tokens you whish to use from the fromVault
        @param minAmountOut The minimal amount of tokens you would expect from the toVault
    */
    function metapoolSwap(
        address fromVault,
        address toVault,
        uint256 amount,
        uint256 minAmountOut
    ) public {
        metapoolSwap(
            fromVault,
            toVault,
            amount,
            minAmountOut,
            _DEFAULT_DONATION,
            _UNKNOWN_ORIGIN
        );
    }

    /**
        @notice swap tokens from one meta pool vault to an other. Overloaded with two extra params.
        @dev Remove funds from a vault, move one side of the asset from one curve pool to an other
        and  deposit into the new vault.
        @param fromVault The vault tokens should be taken from
        @param toVault The vault tokens should be deposited to
        @param amount The amount of tokens you whish to use from the fromVault
        @param minAmountOut The minimal amount of tokens you would expect from the toVault
        @param donation amount of donation to give to Bowswap
        @param origin tracking for partnership
    */
    function metapoolSwap(
        address fromVault,
        address toVault,
        uint256 amount,
        uint256 minAmountOut,
        uint256 donation,
        uint256 origin
    ) public {
        address underlying = IVault(fromVault).token();
        address target = IVault(toVault).token();

        address underlyingPool = _getPoolFromLpToken(underlying);
        address targetPool = _getPoolFromLpToken(target);

        IVault(fromVault).transferFrom(msg.sender, address(this), amount);
        uint256 underlyingAmount = IVault(fromVault).withdraw(
            amount,
            address(this)
        );

        IERC20 underlyingCoin = IERC20(_getCoin(underlyingPool, 1));
        uint256 liquidityAmount = _removeLiquidityOneCoin(
            address(underlyingCoin),
            underlyingPool,
            underlyingAmount,
            1,
            1
        );

        underlyingCoin.approve(targetPool, liquidityAmount);

        IStableSwap(targetPool).add_liquidity(
            [0, liquidityAmount],
            _MIN_AMOUNT_OUT
        );

        uint256 targetAmount = IERC20(target).balanceOf(address(this));
        if (donation != 0) {
            uint256 donating = (targetAmount * donation) / _MAX_DONATION;
            SafeERC20.safeTransfer(IERC20(target), owner, donating);
            targetAmount -= donating;
        }

        _approve(target, toVault, targetAmount);

        uint256 out = IVault(toVault).deposit(targetAmount, msg.sender);

        require(out >= minAmountOut, "out too low");
        if (origin != _UNKNOWN_ORIGIN) {
            emit Orgin(origin);
        }
    }

    /**
        @notice estimate the amount of tokens out
        @param fromVault The vault tokens should be taken from
        @param toVault The vault tokens should be deposited to
        @param amount The amount of tokens you whish to use from the fromVault
        @param donation amount of donation to give to Bowswap
        @return the amount of token shared expected in the toVault
    */
    function metapoolEstimateOut(
        address fromVault,
        address toVault,
        uint256 amount,
        uint256 donation
    ) public view returns (uint256) {
        address underlying = IVault(fromVault).token();
        address target = IVault(toVault).token();

        address underlyingPool = _getPoolFromLpToken(underlying);
        address targetPool = _getPoolFromLpToken(target);

        uint256 pricePerShareFrom = IVault(fromVault).pricePerShare();
        uint256 pricePerShareTo = IVault(toVault).pricePerShare();

        uint256 amountOut = (pricePerShareFrom * amount) /
            (10**IVault(fromVault).decimals());

        amountOut = _calcWithdrawOneCoin(underlyingPool, amountOut, 1);
        amountOut = IStableSwap(targetPool).calc_token_amount(
            [0, amountOut],
            true
        );
        amountOut -= (amountOut * donation) / _MAX_DONATION;
        return (amountOut * (10**IVault(toVault).decimals())) / pricePerShareTo;
    }

    /**
        @notice Swap with approval using eip-2612.
        @param fromVault The vault tokens should be taken from
        @param toVault The vault tokens should be deposited to
        @param amount The amount of tokens you whish to use from the fromVault
        @param minAmountOut The minimal amount of tokens you would expect from the toVault
        @param instructions list of instruction/path to follow to be able to get the desired amount out.
        @param signature signature
    */
    function swapWithSignature(
        address fromVault,
        address toVault,
        uint256 amount,
        uint256 minAmountOut,
        Swap[] calldata instructions,
        uint256 expiry,
        bytes calldata signature
    ) public {
        swapWithSignature(
            fromVault,
            toVault,
            amount,
            minAmountOut,
            instructions,
            expiry,
            signature,
            _DEFAULT_DONATION,
            _UNKNOWN_ORIGIN
        );
    }

    /**
        @notice Swap with approval using eip-2612. Overloaded with two extra params.
        @param fromVault The vault tokens should be taken from
        @param toVault The vault tokens should be deposited to
        @param amount The amount of tokens you whish to use from the fromVault
        @param minAmountOut The minimal amount of tokens you would expect from the toVault
        @param instructions list of instruction/path to follow to be able to get the desired amount out.
        @param signature signature
        @param donation amount of donation to give to Bowswap
        @param origin tracking for partnership
    */
    function swapWithSignature(
        address fromVault,
        address toVault,
        uint256 amount,
        uint256 minAmountOut,
        Swap[] calldata instructions,
        uint256 expiry,
        bytes calldata signature,
        uint256 donation,
        uint256 origin
    ) public {
        assert(
            IVault(fromVault).permit(
                msg.sender,
                address(this),
                amount,
                expiry,
                signature
            )
        );
        swap(
            fromVault,
            toVault,
            amount,
            minAmountOut,
            instructions,
            donation,
            origin
        );
    }

    /**
        @notice Swap tokens from one vault to an other via a Curve pools path.
        @param fromVault The vault tokens should be taken from
        @param toVault The vault tokens should be deposited to
        @param amount The amount of tokens you whish to use from the fromVault
        @param minAmountOut The minimal amount of tokens you would expect from the toVault
        @param instructions list of instruction/path to follow to be able to get the desired amount out.
    */
    function swap(
        address fromVault,
        address toVault,
        uint256 amount,
        uint256 minAmountOut,
        Swap[] calldata instructions
    ) public {
        swap(
            fromVault,
            toVault,
            amount,
            minAmountOut,
            instructions,
            _DEFAULT_DONATION,
            _UNKNOWN_ORIGIN
        );
    }

    /**
        @notice Swap tokens from one vault to an other via a Curve pools path. Overloaded with two extra params.
        @param fromVault The vault tokens should be taken from
        @param toVault The vault tokens should be deposited to
        @param amount The amount of tokens you whish to use from the fromVault
        @param minAmountOut The minimal amount of tokens you would expect from the toVault
        @param instructions list of instruction/path to follow to be able to get the desired amount out.
        @param donation amount of donation to give to Bowswap
        @param origin tracking for partnership
    */
    // solhint-disable-next-line function-max-lines, code-complexity
    function swap(
        address fromVault,
        address toVault,
        uint256 amount,
        uint256 minAmountOut,
        Swap[] calldata instructions,
        uint256 donation,
        uint256 origin
    ) public {
        address token = IVault(fromVault).token();
        address target = IVault(toVault).token();

        IVault(fromVault).transferFrom(msg.sender, address(this), amount);
        amount = IVault(fromVault).withdraw(amount, address(this));

        uint256 nCoins;
        for (uint256 i = 0; i < instructions.length; i++) {
            if (instructions[i].action == Action.Deposit) {
                nCoins = _getNCoins(instructions[i].pool);
                uint256[] memory list = new uint256[](nCoins);
                list[instructions[i].n] = amount;
                _approve(token, instructions[i].pool, amount);

                if (nCoins == 2) {
                    IStableSwap(instructions[i].pool).add_liquidity(
                        [list[0], list[1]],
                        1
                    );
                } else if (nCoins == 3) {
                    IStableSwap(instructions[i].pool).add_liquidity(
                        [list[0], list[1], list[2]],
                        1
                    );
                } else if (nCoins == 4) {
                    IStableSwap(instructions[i].pool).add_liquidity(
                        [list[0], list[1], list[2], list[3]],
                        1
                    );
                }

                token = _getLpTokenFromPool(instructions[i].pool);
                amount = IERC20(token).balanceOf(address(this));
            } else if (instructions[i].action == Action.Withdraw) {
                token = _getCoin(instructions[i].pool, instructions[i].n);
                amount = _removeLiquidityOneCoin(
                    token,
                    instructions[i].pool,
                    amount,
                    instructions[i].n,
                    1
                );
            } else {
                _approve(token, instructions[i].pool, amount);
                token = _getCoin(instructions[i].pool, instructions[i].m);
                amount = _exchange(
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
            uint256 donating = (amount * donation) / _MAX_DONATION;
            SafeERC20.safeTransfer(IERC20(target), owner, donating);
            amount -= donating;
        }
        _approve(target, toVault, amount);
        require(
            IVault(toVault).availableDepositLimit() >= amount,
            "!depositLimit"
        );
        uint256 out = IVault(toVault).deposit(amount, msg.sender);

        require(out >= minAmountOut, "out too low");
        if (origin != _UNKNOWN_ORIGIN) {
            emit Orgin(origin);
        }
    }

    /**
        @notice Wrapper around the pool function remove_liquidity_one_coin. This function does not have any return value, so we wrap a balanceOf before and
        after to get the updated amount.
        @dev Tricrypto pool does not have the same signature and should be handle differently.
        @param token Token that should be removed from pool
        @param pool Address of the curve pool to work with
        @param amount The amount of tokens we want to remove
        @param i Index in the coins of the pool to remove. pool.coins[n] should be equal to token
        @param minAmount The minimal amount of tokens you would expect
        @return the new amount of tokens available
    */
    function _removeLiquidityOneCoin(
        address token,
        address pool,
        uint256 amount,
        uint128 i,
        uint256 minAmount
    ) internal returns (uint256) {
        uint256 amountBefore = IERC20(token).balanceOf(address(this));
        if (pool == _TRI_CRYPTO_POOL) {
            IStableSwap(pool).remove_liquidity_one_coin(
                amount,
                uint256(i),
                minAmount
            );
        } else {
            IStableSwap(pool).remove_liquidity_one_coin(
                amount,
                int128(i),
                minAmount
            );
        }
        uint256 newAmount = IERC20(token).balanceOf(address(this));
        require(newAmount > amountBefore, "!remove");
        return newAmount;
    }

    /**
        @notice estimate the amount of tokens out for a standard swap
        @param fromVault The vault tokens should be taken from
        @param toVault The vault tokens should be deposited to
        @param amount The amount of tokens you whish to use from the fromVault
        @param instructions list of instruction/path to follow to be able to get the desired amount
        @param donation amount of donation to give to Bowswap
        @return the amount of token shared expected in the toVault
    */
    // solhint-disable-next-line function-max-lines
    function estimateOut(
        address fromVault,
        address toVault,
        uint256 amount,
        Swap[] calldata instructions,
        uint256 donation
    ) public view returns (uint256) {
        uint256 pricePerShareFrom = IVault(fromVault).pricePerShare();
        uint256 pricePerShareTo = IVault(toVault).pricePerShare();
        amount =
            (amount * pricePerShareFrom) /
            (10**IVault(fromVault).decimals());
        for (uint256 i = 0; i < instructions.length; i++) {
            uint256 nCoins = _getViewNCoins(instructions[i].pool);
            if (instructions[i].action == Action.Deposit) {
                nCoins = _getViewNCoins(instructions[i].pool);
                uint256[] memory list = new uint256[](nCoins);
                list[instructions[i].n] = amount;

                if (nCoins == 2) {
                    try
                        IStableSwap(instructions[i].pool).calc_token_amount(
                            [list[0], list[1]],
                            true
                        )
                    returns (uint256 _amount) {
                        amount = _amount;
                    } catch {
                        amount = IStableSwap(instructions[i].pool)
                            .calc_token_amount([list[0], list[1]]);
                    }
                } else if (nCoins == 3) {
                    try
                        IStableSwap(instructions[i].pool).calc_token_amount(
                            [list[0], list[1], list[2]],
                            true
                        )
                    returns (uint256 _amount) {
                        amount = _amount;
                    } catch {
                        amount = IStableSwap(instructions[i].pool)
                            .calc_token_amount([list[0], list[1], list[2]]);
                    }
                } else if (nCoins == 4) {
                    try
                        IStableSwap(instructions[i].pool).calc_token_amount(
                            [list[0], list[1], list[2], list[3]],
                            true
                        )
                    returns (uint256 _amount) {
                        amount = _amount;
                    } catch {
                        amount = IStableSwap(instructions[i].pool)
                            .calc_token_amount(
                                [list[0], list[1], list[2], list[3]]
                            );
                    }
                }
            } else if (instructions[i].action == Action.Withdraw) {
                amount = _calcWithdrawOneCoin(
                    instructions[i].pool,
                    amount,
                    instructions[i].n
                );
            } else {
                amount = _calcExchange(
                    instructions[i].pool,
                    amount,
                    instructions[i].n,
                    instructions[i].m
                );
            }
        }
        amount -= (amount * donation) / _MAX_DONATION;
        return (amount * (10**IVault(toVault).decimals())) / pricePerShareTo;
    }

    /**
        @notice Safer approve that will check for allowance and reset approval before giving it.
        @param target erc20 to approve
        @param toVault The operator
        @param amount The amount of tokens you whish to use from the target
    */
    function _approve(
        address target,
        address toVault,
        uint256 amount
    ) internal {
        uint256 allowance = IERC20(target).allowance(address(this), toVault);
        if (allowance < amount) {
            if (allowance != 0) {
                SafeERC20.safeApprove(IERC20(target), toVault, 0);
            }
            SafeERC20.safeApprove(IERC20(target), toVault, type(uint256).max);
        }
    }

    /**
        @notice Wrapper around the pool function calc_withdraw_one_coin.
        @dev Tricrypto pool does not have the same signature and should be handle differently.
        @param pool Address of the curve pool to work with
        @param amount The amount of tokens we want to swap
        @param n Index in the coins of the pool we want to withdraw.
        @return the expected amount withdrawn from the pool
    */
    function _calcWithdrawOneCoin(
        address pool,
        uint256 amount,
        uint128 n
    ) internal view returns (uint256) {
        if (pool == _TRI_CRYPTO_POOL) {
            return IStableSwap(pool).calc_withdraw_one_coin(amount, uint256(n));
        }
        return IStableSwap(pool).calc_withdraw_one_coin(amount, int128(n));
    }

    /**
        @notice Wrapper around the pool function get_coin.
        @dev A pool can be registered either in the registry or in the factory registry, so we need to find in which it is used.
        @param pool Address of the curve pool to work with
        @param n Index in the coins we want to get.
        @return the address of the token at index n
    */
    function _getCoin(address pool, uint256 n) internal view returns (address) {
        address token = _REGISTRY.get_coins(pool)[n];
        if (token != address(0x0)) return token;
        return _FACTORY_REGISTRY.get_coins(pool)[n];
    }

    /**
        @notice Wrapper around the pool function get_pool_from_lp_token.
        @dev A pool can be registered either in the registry or in the factory registry, so we need to find in which it is used.
        @param lp Address of the curve LP token to work with
        @return the pool with the relevant function, or the LP address if the pool is the LP
    */
    function _getPoolFromLpToken(address lp) internal view returns (address) {
        address pool = _REGISTRY.get_pool_from_lp_token(lp);
        if (pool == address(0x0)) {
            return lp;
        }
        return pool;
    }

    /**
        @notice Wrapper around the pool function exchange. This function does not have any return value, so we wrap a balanceOf before and after to get the
        updated amount.
        @dev Tricrypto pool does not have the same signature and should be handle differently.
        @param token Token that should be removed from pool
        @param pool Address of the curve pool to work with
        @param amount The amount of tokens we want to swap
        @param n Index in the coins of the pool to swap as from.
        @param m Index in the coins of the pool to swap as to.
        @return the new amount of tokens available
    */
    function _exchange(
        address token,
        address pool,
        uint256 amount,
        uint128 n,
        uint128 m
    ) internal returns (uint256) {
        uint256 amountBefore = IERC20(token).balanceOf(address(this));
        if (pool == _TRI_CRYPTO_POOL) {
            IStableSwap(pool).exchange(
                uint256(n),
                uint256(m),
                amount,
                1,
                false
            );
        } else {
            IStableSwap(pool).exchange(int128(n), int128(m), amount, 1);
        }
        uint256 newAmount = IERC20(token).balanceOf(address(this));
        require(newAmount > amountBefore, "!exchange");
        return newAmount;
    }

    /**
        @notice Wrapper around the pool function get_dy.
        @dev Tricrypto pool does not have the same signature and should be handle differently.
        @param pool address of the curve pool to use
        @param amount amount to swap
        @param n index of the first token to exchange
        @param m index of the second token to exchange
        @return the pool with the relevant function, or the LP address if the pool is the LP
    */
    function _calcExchange(
        address pool,
        uint256 amount,
        uint128 n,
        uint128 m
    ) internal view returns (uint256) {
        if (pool == _TRI_CRYPTO_POOL) {
            return IStableSwap(pool).get_dy(uint256(n), uint256(m), amount);
        }
        return IStableSwap(pool).get_dy(int128(n), int128(m), amount);
    }

    /**
        @notice Wrapper around the pool function get_lp_token.
        @dev A pool can be registered either in the registry or in the factory registry, so we need to find in which it is used.
        @param pool Address of the curve Pool to work with
        @return the LP token address for this pool if available of the pool address as fallback
    */
    function _getLpTokenFromPool(address pool) internal view returns (address) {
        address token = _REGISTRY.get_lp_token(pool);
        if (token != address(0x0)) return token;
        return pool;
    }

    /**
        @notice Function to get the number of coins in a specific pool.
        @dev We cannot count on get_n_coins for the factory_registry because some pools, with coin, have a 0 return value. We have a local `num_coins` mapping
        which is init by this function and is used if available. Otherwise we try to get and count the number of coins for a specific pool.
        @param pool Address of the curve Pool to work with
        @return The number of coins in this pool
    */
    function _getNCoins(address pool) internal returns (uint256) {
        uint256 num = numCoins[pool];
        if (num != 0) return num;

        num = _REGISTRY.get_n_coins(pool)[0];
        if (num != 0) {
            numCoins[pool] = num;
            return num;
        }

        address[4] memory coins = _FACTORY_REGISTRY.get_coins(pool);
        for (uint256 index = 0; index < coins.length; index++) {
            if (coins[index] != address(0)) {
                num++;
            }
        }
        numCoins[pool] = num;
        return num;
    }

    /**
        @notice Function to get the number of coins in a specific pool.
        @param pool Address of the curve Pool to work with
        @return The number of coins in this pool
    */
    function _getViewNCoins(address pool) internal view returns (uint256) {
        uint256 num = numCoins[pool];
        if (num != 0) return num;

        num = _REGISTRY.get_n_coins(pool)[0];
        if (num != 0) return num;

        address[4] memory coins = _FACTORY_REGISTRY.get_coins(pool);
        for (uint256 index = 0; index < coins.length; index++) {
            if (coins[index] != address(0)) {
                num++;
            }
        }
        return num;
    }
}
