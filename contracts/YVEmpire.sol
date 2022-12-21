// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ILendingPool.sol";
import "./interfaces/IATokenV1.sol";
import "./interfaces/IATokenV2.sol";
import "./interfaces/ICToken.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IYearnRegistry.sol";
import "./interfaces/IBeefyVault.sol";

contract YVEmpire {
    IYearnRegistry private immutable _registry;
    ILendingPool private immutable _lendingPoolV2;
    ILendingPool private immutable _lendingPoolV3;

    struct Swap {
        uint8 service;
        address coin;
        uint256 amount;
    }

    constructor(
        address registry,
        address lendingPoolV2,
        address lendingPoolV3
    ) {
        _registry = IYearnRegistry(registry);
        _lendingPoolV2 = ILendingPool(lendingPoolV2);
        _lendingPoolV3 = ILendingPool(lendingPoolV3);
    }

    function migrate(Swap calldata swap) external returns (uint256) {
        return _migrate(swap);
    }

    function migrate(Swap[] calldata swaps)
        external
        returns (uint256[] memory)
    {
        uint256 length = swaps.length;
        uint256[] memory amounts = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            amounts[i] = _migrate(swaps[i]);
        }
        return amounts;
    }

    function _migrate(Swap calldata swap) internal returns (uint256) {
        address underlying;
        uint256 amount = _transferToSelf(swap.coin, swap.amount);
        if (swap.service == 0) {
            underlying = _swapCompound(swap.coin, amount);
        } else if (swap.service == 1) {
            underlying = _swapAaveV1(swap.coin);
        } else if (swap.service == 2) {
            underlying = _swapAave(swap.coin, _lendingPoolV2);
        } else if (swap.service == 3) {
            underlying = _swapAave(swap.coin, _lendingPoolV3);
        } else if (swap.service == 4) {
            underlying = _swapBeefy(swap.coin);
        }
        return _depositIntoVault(underlying);
    }

    function _transferToSelf(address coin, uint256 amount)
        internal
        returns (uint256)
    {
        IERC20 token = IERC20(coin);
        if (amount == type(uint256).max) {
            amount = Math.min(
                token.balanceOf(msg.sender),
                token.allowance(msg.sender, address(this))
            );
        }
        require(amount > 0, "!amount");
        SafeERC20.safeTransferFrom(token, msg.sender, address(this), amount);
        return amount;
    }

    function _depositIntoVault(address token) internal returns (uint256) {
        uint256 balance = IERC20(token).balanceOf(address(this));
        IVault vault = IVault(_registry.latestVault(address(token)));
        SafeERC20.safeApprove(IERC20(token), address(vault), balance);
        return vault.deposit(balance, msg.sender);
    }

    function _swapCompound(address coin, uint256 amount)
        internal
        returns (address)
    {
        ICToken cToken = ICToken(coin);
        require(cToken.redeem(amount) == 0, "!redeem");

        return cToken.underlying();
    }

    function _swapAaveV1(address coin) internal returns (address) {
        IATokenV1 aToken = IATokenV1(coin);
        aToken.redeem(type(uint256).max);

        return aToken.underlyingAssetAddress();
    }

    function _swapAave(address coin, ILendingPool lendingPool)
        internal
        returns (address)
    {
        address underlying = IATokenV2(coin).UNDERLYING_ASSET_ADDRESS();
        lendingPool.withdraw(underlying, type(uint256).max, address(this));
        return underlying;
    }

    function _swapBeefy(address coin) internal returns (address) {
        address underlying = IBeefyVault(coin).want();
        IBeefyVault(coin).withdrawAll();
        return underlying;
    }

    // Estimate functions

    function estimate(Swap calldata swap) external view returns (uint256) {
        return _estimate(swap);
    }

    function estimate(Swap[] calldata swaps)
        external
        view
        returns (uint256[] memory)
    {
        uint256 length = swaps.length;
        uint256[] memory amounts = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            amounts[i] = _estimate(swaps[i]);
        }
        return amounts;
    }

    function _estimate(Swap calldata swap) internal view returns (uint256) {
        address underlying;
        uint256 amount;
        if (swap.service == 0) {
            amount = _estimateCompound(swap);
            underlying = ICToken(swap.coin).underlying();
        } else if (swap.service == 1) {
            amount = swap.amount;
            underlying = IATokenV1(swap.coin).underlyingAssetAddress();
        } else if (swap.service == 2 || swap.service == 3) {
            amount = swap.amount;
            underlying = IATokenV2(swap.coin).UNDERLYING_ASSET_ADDRESS();
        } else if (swap.service == 4) {
            amount = _estimateBeefy(swap);
            underlying = IBeefyVault(swap.coin).want();
        }
        address vault = _registry.latestVault(underlying);
        return
            (amount * 10**IERC20Metadata(underlying).decimals()) /
            IVault(vault).pricePerShare();
    }

    function _estimateCompound(Swap memory swap)
        internal
        view
        returns (uint256)
    {
        return (swap.amount * _compoundExchangeRateCurrent(swap.coin)) / 10**18;
    }

    function _compoundExchangeRateCurrent(address coin)
        internal
        view
        returns (uint256)
    {
        return
            (10**18 *
                (ICToken(coin).getCash() +
                    ICToken(coin).totalBorrows() -
                    ICToken(coin).totalReserves())) /
            ICToken(coin).totalSupply();
    }

    function _estimateBeefy(Swap memory swap) internal view returns (uint256) {
        return
            (IBeefyVault(swap.coin).getPricePerFullShare() * swap.amount) /
            10**18;
    }
}
