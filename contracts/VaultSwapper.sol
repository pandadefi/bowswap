// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;
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
    address public owner;

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

    /*
        @notice Swap with apoval using eip-2612
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
        @dev Remove funds from a vault, move one side of 
        the asset from one curve pool to an other and 
        deposit into the new vault.
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
        IStableSwap(underlyingPool).remove_liquidity_one_coin(
            underlyingAmount,
            1,
            1
        );

        IERC20 underlyingCoin = IERC20(_getCoin(underlyingPool, 1));
        uint256 liquidityAmount = underlyingCoin.balanceOf(address(this));

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
        amountOut = IStableSwap(underlyingPool).calc_withdraw_one_coin(
            amountOut,
            1
        );
        amountOut = IStableSwap(targetPool).calc_token_amount(
            [0, amountOut],
            true
        );
        amountOut -= (amountOut * donation) / _MAX_DONATION;
        return (amountOut * (10**IVault(toVault).decimals())) / pricePerShareTo;
    }

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
                    instructions[i].n
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
        uint256 out = IVault(toVault).deposit(amount, msg.sender);

        require(out >= minAmountOut, "out too low");
        if (origin != _UNKNOWN_ORIGIN) {
            emit Orgin(origin);
        }
    }

    function _removeLiquidityOneCoin(
        address token,
        address pool,
        uint256 amount,
        uint128 n
    ) internal returns (uint256) {
        uint256 amountBefore = IERC20(token).balanceOf(address(this));
        // solhint-disable-next-line avoid-low-level-calls
        pool.call(
            abi.encodeWithSignature(
                "remove_liquidity_one_coin(uint256,uint256,uint256)",
                amount,
                uint256(n),
                1
            )
        );
        uint256 newAmount = IERC20(token).balanceOf(address(this));

        if (newAmount > amountBefore) {
            return newAmount;
        }
        // solhint-disable-next-line avoid-low-level-calls
        pool.call(
            abi.encodeWithSignature(
                "remove_liquidity_one_coin(uint256,int128,uint256)",
                amount,
                int128(n),
                1
            )
        );

        newAmount = IERC20(token).balanceOf(address(this));
        require(newAmount > amountBefore, "!remove");

        return newAmount;
    }

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
            uint256 nCoins = _getNCoins(instructions[i].pool);
            if (instructions[i].action == Action.Deposit) {
                nCoins = _getNCoins(instructions[i].pool);
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

    function _calcWithdrawOneCoin(
        address pool,
        uint256 amount,
        uint128 n
    ) internal view returns (uint256) {
        (bool success, bytes memory returnData) = pool.staticcall(
            abi.encodeWithSignature(
                "calc_withdraw_one_coin(uint256,uint256)",
                amount,
                uint256(n)
            )
        );
        if (success) {
            return abi.decode(returnData, (uint256));
        }
        (success, returnData) = pool.staticcall(
            abi.encodeWithSignature(
                "calc_withdraw_one_coin(uint256,int128)",
                amount,
                int128(n)
            )
        );

        require(success, "!success");

        return abi.decode(returnData, (uint256));
    }

    function _getCoin(address pool, uint256 n) internal view returns (address) {
        address token = _REGISTRY.get_coins(pool)[n];
        if (token != address(0x0)) return token;
        return _FACTORY_REGISTRY.get_coins(pool)[n];
    }

    function _getPoolFromLpToken(address lp) internal view returns (address) {
        address pool = _REGISTRY.get_pool_from_lp_token(lp);
        if (pool == address(0x0)) {
            return lp;
        } else {
            return pool;
        }
    }

    function _exchange(
        address token,
        address pool,
        uint256 amount,
        uint128 n,
        uint128 m
    ) internal returns (uint256) {
        uint256 amountBefore = IERC20(token).balanceOf(address(this));

        // solhint-disable-next-line avoid-low-level-calls
        pool.call(
            abi.encodeWithSignature(
                "exchange(uint256,uint256,uint256,uint256)",
                uint256(n),
                uint256(m),
                amount,
                1
            )
        );

        uint256 newAmount = IERC20(token).balanceOf(address(this));

        if (newAmount > amountBefore) {
            return newAmount;
        }

        // solhint-disable-next-line avoid-low-level-calls
        pool.call(
            abi.encodeWithSignature(
                "exchange(int128,int128,uint256,uint256)",
                int128(n),
                int128(m),
                amount,
                1
            )
        );

        newAmount = IERC20(token).balanceOf(address(this));
        require(newAmount > amountBefore, "!exchange");
        return newAmount;
    }

    // solhint-disable-next-line avoid-low-level-calls
    function _calcExchange(
        address pool,
        uint256 amount,
        uint128 n,
        uint128 m
    ) internal view returns (uint256) {
        (bool success, bytes memory returnData) = pool.staticcall(
            abi.encodeWithSignature(
                "get_dy(uint256,uint256,uint256)",
                uint256(n),
                uint256(m),
                amount
            )
        );
        if (success) {
            return abi.decode(returnData, (uint256));
        }
        (success, returnData) = pool.staticcall(
            abi.encodeWithSignature(
                "get_dy(int128,int128,uint256)",
                int128(n),
                int128(m),
                amount
            )
        );

        require(success, "!success");

        return abi.decode(returnData, (uint256));
    }

    function _getLpTokenFromPool(address pool) internal view returns (address) {
        address token = _REGISTRY.get_lp_token(pool);
        if (token != address(0x0)) return token;
        return pool;
    }

    function _getNCoins(address pool) internal view returns (uint256) {
        uint256 num = _REGISTRY.get_n_coins(pool)[0];
        if (num != 0) return num;
        return _FACTORY_REGISTRY.get_n_coins(pool);
    }
}
