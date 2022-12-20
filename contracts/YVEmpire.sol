// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ILendingPool.sol";
import "./interfaces/IATokenV1.sol";
import "./interfaces/IATokenV2.sol";
import "./interfaces/ICToken.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IYearnRegistry.sol";

contract YVEmpire {
    IYearnRegistry private immutable _registry;
    ILendingPool private immutable _lendingPoolV2;
    ILendingPool private immutable _lendingPoolV3;

    struct Swap {
        uint8 service;
        address coin;
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
        if (swap.service == 0) {
            underlying = _swapCompound(swap.coin);
        } else if (swap.service == 1) {
            underlying = _swapAaveV1(swap.coin);
        } else if (swap.service == 2) {
            underlying = _swapAave(swap.coin, _lendingPoolV2);
        } else if (swap.service == 3) {
            underlying = _swapAave(swap.coin, _lendingPoolV3);
        }
        return _depositIntoVault(underlying);
    }

    function _transferToSelf(address coin) internal returns (uint256) {
        IERC20 token = IERC20(coin);
        uint256 amount = Math.min(
            token.balanceOf(msg.sender),
            token.allowance(msg.sender, address(this))
        );
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

    function _swapCompound(address coin) internal returns (address) {
        uint256 amount = _transferToSelf(coin);
        ICToken cToken = ICToken(coin);
        require(cToken.redeem(amount) == 0, "!redeem");

        return cToken.underlying();
    }

    function _swapAaveV1(address coin) internal returns (address) {
        _transferToSelf(coin);
        IATokenV1 aToken = IATokenV1(coin);
        aToken.redeem(type(uint256).max);

        return aToken.underlyingAssetAddress();
    }

    function _swapAave(address coin, ILendingPool lendingPool)
        internal
        returns (address)
    {
        _transferToSelf(coin);
        address underlying = IATokenV2(coin).UNDERLYING_ASSET_ADDRESS();
        lendingPool.withdraw(underlying, type(uint256).max, address(this));
        return underlying;
    }
}
