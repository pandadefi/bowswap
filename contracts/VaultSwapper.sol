// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IStableSwap.sol";
import "./interfaces/ICurveRegistry.sol";
import "./interfaces/ICurveFactoryRegistry.sol";

contract VaultSwapper is Initializable {
    ICurveRegistry constant registry =
        ICurveRegistry(0x90E00ACe148ca3b23Ac1bC8C240C2a7Dd9c2d7f5);
    ICurveFactoryRegistry constant factory_registry =
        ICurveFactoryRegistry(0xB9fC157394Af804a3578134A6585C0dc9cc990d4);

    uint256 private constant MIN_AMOUNT_OUT = 1;
    uint256 private constant MAX_DONATION = 10_000;
    uint256 private constant DEFAULT_DONATION = 30;
    uint256 private constant UNKNOWN_ORIGIN = 0;
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

    function set_owner(address new_owner) public {
        require(owner == msg.sender);
        require(new_owner != address(0));
        owner = new_owner;
    }

    /*
        @notice Swap with apoval using eip-2612
        @param from_vault The vault tokens should be taken from
        @param to_vault The vault tokens should be deposited to
        @param amount The amount of tokens you whish to use from the from_vault
        @param min_amount_out The minimal amount of tokens you would expect from the to_vault
        @param expiry signature expiry
        @param signature signature
    */
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
            IVault(from_vault).permit(
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

    /**
        @notice swap tokens from one meta pool vault to an other
        @dev Remove funds from a vault, move one side of 
        the asset from one curve pool to an other and 
        deposit into the new vault.
        @param from_vault The vault tokens should be taken from
        @param to_vault The vault tokens should be deposited to
        @param amount The amount of tokens you whish to use from the from_vault
        @param min_amount_out The minimal amount of tokens you would expect from the to_vault
    */
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

    function metapool_swap(
        address from_vault,
        address to_vault,
        uint256 amount,
        uint256 min_amount_out,
        uint256 donation,
        uint256 origin
    ) public {
        address underlying = IVault(from_vault).token();
        address target = IVault(to_vault).token();

        address underlying_pool = _get_pool_from_lp_token(underlying);
        address target_pool = _get_pool_from_lp_token(target);

        IVault(from_vault).transferFrom(msg.sender, address(this), amount);
        uint256 underlying_amount = IVault(from_vault).withdraw(
            amount,
            address(this)
        );
        IStableSwap(underlying_pool).remove_liquidity_one_coin(
            underlying_amount,
            1,
            1
        );

        IERC20 underlying_coin = IERC20(_get_coin(underlying_pool, 1));
        uint256 liquidity_amount = underlying_coin.balanceOf(address(this));

        underlying_coin.approve(target_pool, liquidity_amount);

        IStableSwap(target_pool).add_liquidity(
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

        uint256 out = IVault(to_vault).deposit(target_amount, msg.sender);

        require(out >= min_amount_out, "out too low");
        if (origin != UNKNOWN_ORIGIN) {
            emit Orgin(origin);
        }
    }

    /**
        @notice estimate the amount of tokens out
        @param from_vault The vault tokens should be taken from
        @param to_vault The vault tokens should be deposited to
        @param amount The amount of tokens you whish to use from the from_vault
        @return the amount of token shared expected in the to_vault
     */
    function metapool_estimate_out(
        address from_vault,
        address to_vault,
        uint256 amount,
        uint256 donation
    ) public view returns (uint256) {
        address underlying = IVault(from_vault).token();
        address target = IVault(to_vault).token();

        address underlying_pool = _get_pool_from_lp_token(underlying);
        address target_pool = _get_pool_from_lp_token(target);

        uint256 pricePerShareFrom = IVault(from_vault).pricePerShare();
        uint256 pricePerShareTo = IVault(to_vault).pricePerShare();

        uint256 amount_out = (pricePerShareFrom * amount) /
            (10**IVault(from_vault).decimals());
        amount_out = IStableSwap(underlying_pool).calc_withdraw_one_coin(
            amount_out,
            1
        );
        amount_out = IStableSwap(target_pool).calc_token_amount(
            [0, amount_out],
            true
        );
        amount_out -= (amount_out * donation) / MAX_DONATION;
        return
            (amount_out * (10**IVault(to_vault).decimals())) / pricePerShareTo;
    }

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
            IVault(from_vault).permit(
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

    function swap(
        address from_vault,
        address to_vault,
        uint256 amount,
        uint256 min_amount_out,
        Swap[] calldata instructions,
        uint256 donation,
        uint256 origin
    ) public {
        address token = IVault(from_vault).token();
        address target = IVault(to_vault).token();

        IVault(from_vault).transferFrom(msg.sender, address(this), amount);
        amount = IVault(from_vault).withdraw(amount, address(this));

        uint256 n_coins;
        for (uint256 i = 0; i < instructions.length; i++) {
            if (instructions[i].action == Action.Deposit) {
                n_coins = _get_n_coins(instructions[i].pool);
                uint256[] memory list = new uint256[](n_coins);
                list[instructions[i].n] = amount;
                approve(token, instructions[i].pool, amount);

                if (n_coins == 2) {
                    IStableSwap(instructions[i].pool).add_liquidity(
                        [list[0], list[1]],
                        1
                    );
                } else if (n_coins == 3) {
                    IStableSwap(instructions[i].pool).add_liquidity(
                        [list[0], list[1], list[2]],
                        1
                    );
                } else if (n_coins == 4) {
                    IStableSwap(instructions[i].pool).add_liquidity(
                        [list[0], list[1], list[2], list[3]],
                        1
                    );
                }

                token = _get_lp_token_from_pool(instructions[i].pool);
                amount = IERC20(token).balanceOf(address(this));
            } else if (instructions[i].action == Action.Withdraw) {
                token = _get_coin(instructions[i].pool, instructions[i].n);
                amount = remove_liquidity_one_coin(
                    token,
                    instructions[i].pool,
                    amount,
                    instructions[i].n
                );
            } else {
                approve(token, instructions[i].pool, amount);
                token = _get_coin(instructions[i].pool, instructions[i].m);
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
            uint256 donating = (amount * donation) / MAX_DONATION;
            SafeERC20.safeTransfer(IERC20(target), owner, donating);
            amount -= donating;
        }
        approve(target, to_vault, amount);
        uint256 out = IVault(to_vault).deposit(amount, msg.sender);

        require(out >= min_amount_out, "out too low");
        if (origin != UNKNOWN_ORIGIN) {
            emit Orgin(origin);
        }
    }

    function remove_liquidity_one_coin(
        address token,
        address pool,
        uint256 amount,
        uint128 n
    ) internal returns (uint256) {
        uint256 amountBefore = IERC20(token).balanceOf(address(this));
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

    function estimate_out(
        address from_vault,
        address to_vault,
        uint256 amount,
        Swap[] calldata instructions,
        uint256 donation
    ) public view returns (uint256) {
        uint256 pricePerShareFrom = IVault(from_vault).pricePerShare();
        uint256 pricePerShareTo = IVault(to_vault).pricePerShare();
        amount =
            (amount * pricePerShareFrom) /
            (10**IVault(from_vault).decimals());
        for (uint256 i = 0; i < instructions.length; i++) {
            uint256 n_coins = _get_n_coins(instructions[i].pool);
            if (instructions[i].action == Action.Deposit) {
                n_coins = _get_n_coins(instructions[i].pool);
                uint256[] memory list = new uint256[](n_coins);
                list[instructions[i].n] = amount;

                if (n_coins == 2) {
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
                } else if (n_coins == 3) {
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
                } else if (n_coins == 4) {
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
                amount = _calc_withdraw_one_coin(
                    instructions[i].pool,
                    amount,
                    instructions[i].n
                );
            } else {
                amount = _calc_exchange(
                    instructions[i].pool,
                    amount,
                    instructions[i].n,
                    instructions[i].m
                );
            }
        }
        amount -= (amount * donation) / MAX_DONATION;
        return (amount * (10**IVault(to_vault).decimals())) / pricePerShareTo;
    }

    function approve(
        address target,
        address to_vault,
        uint256 amount
    ) internal {
        uint256 allowance = IERC20(target).allowance(address(this), to_vault);
        if (allowance < amount) {
            if (allowance != 0) {
                SafeERC20.safeApprove(IERC20(target), to_vault, 0);
            }
            SafeERC20.safeApprove(IERC20(target), to_vault, type(uint256).max);
        }
    }

    function _calc_withdraw_one_coin(
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

    function _get_coin(address pool, uint256 n)
        internal
        view
        returns (address)
    {
        address token = registry.get_coins(pool)[n];
        if (token != address(0x0)) return token;
        return factory_registry.get_coins(pool)[n];
    }

    function _get_pool_from_lp_token(address lp)
        internal
        view
        returns (address)
    {
        address pool = registry.get_pool_from_lp_token(lp);
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

    function _calc_exchange(
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

    function _get_lp_token_from_pool(address pool)
        internal
        view
        returns (address)
    {
        address token = registry.get_lp_token(pool);
        if (token != address(0x0)) return token;
        return pool;
    }

    function _get_n_coins(address pool) internal view returns (uint256) {
        uint256 num = registry.get_n_coins(pool)[0];
        if (num != 0) return num;
        return factory_registry.get_n_coins(pool);
    }
}
