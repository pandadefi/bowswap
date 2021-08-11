// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface LendingPool {
    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external;
}

interface ATokenV1 {
    function underlyingAssetAddress() external returns (address);

    function redeem(uint256 _amount) external;
}

interface ATokenV2 {
    function UNDERLYING_ASSET_ADDRESS() external returns (address);
}

interface CToken {
    function redeem(uint256 redeemTokens) external returns (uint256);

    function balanceOf(address account) external returns (uint256);

    function allowance(address owner, address spender)
        external
        returns (uint256);

    function underlying() external returns (address);
}

interface Registry {
    function latestVault(address) external returns (address);
}

interface Vault {
    function deposit(uint256 amount) external returns (uint256);

    function transfer(address to, uint256 amount) external;
}

contract YVEmpire {
    Registry registry = Registry(0x50c1a2eA0a861A967D9d0FFE2AE4012c2E053804);
    LendingPool lendingPool =
        LendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);

    enum Service {
        Compound,
        Aavev1,
        Aavev2
    }
    struct Swap {
        Service service;
        address coin;
    }

    function migrate(Swap[] calldata swaps) public {
        for (uint256 i = 0; i < swaps.length; i++) {
            if (swaps[i].service == Service.Compound) {
                swapCompound(swaps[i].coin);
            } else if (swaps[i].service == Service.Aavev1) {
                swapAaveV1(swaps[i].coin);
            } else if (swaps[i].service == Service.Aavev2) {
                swapAaveV2(swaps[i].coin);
            }
        }
    }

    function transferToSelf(address coin) internal returns (uint256) {
        IERC20 token = IERC20(coin);
        uint256 amount = Math.min(
            token.balanceOf(msg.sender),
            token.allowance(msg.sender, address(this))
        );
        SafeERC20.safeTransferFrom(token, msg.sender, address(this), amount);
        return amount;
    }

    function approve(
        IERC20 token,
        address spender,
        uint256 amount
    ) internal {
        if (token.allowance(address(this), spender) < amount) {
            SafeERC20.safeApprove(token, spender, type(uint256).max);
        }
    }

    function depositIntoVault(IERC20 token) internal {
        uint256 balance = token.balanceOf(address(this));
        Vault vault = Vault(registry.latestVault(address(token)));
        approve(token, address(vault), balance);
        uint256 vaultBalance = vault.deposit(balance);
        vault.transfer(msg.sender, vaultBalance);
    }

    function swapCompound(address coin) internal {
        uint256 amount = transferToSelf(coin);
        CToken cToken = CToken(coin);
        IERC20 underlying = IERC20(cToken.underlying());
        Vault vault = Vault(registry.latestVault(address(underlying)));
        require(cToken.redeem(amount) == 0, "!redeem");

        depositIntoVault(underlying);
    }

    function swapAaveV1(address coin) internal {
        uint256 amount = transferToSelf(coin);
        ATokenV1 aToken = ATokenV1(coin);
        IERC20 underlying = IERC20(aToken.underlyingAssetAddress());
        aToken.redeem(type(uint256).max);

        depositIntoVault(underlying);
    }

    function swapAaveV2(address coin) internal {
        uint256 amount = transferToSelf(coin);
        IERC20 underlying = IERC20(ATokenV2(coin).UNDERLYING_ASSET_ADDRESS());
        lendingPool.withdraw(
            address(underlying),
            type(uint256).max,
            address(this)
        );
        depositIntoVault(underlying);
    }
}
