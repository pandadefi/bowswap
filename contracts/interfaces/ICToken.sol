// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface ICToken {
    function redeem(uint256 redeemTokens) external returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function allowance(address owner, address spender)
        external
        returns (uint256);

    function underlying() external view returns (address);

    function getCash() external view returns (uint256);

    function totalBorrows() external view returns (uint256);

    function totalReserves() external view returns (uint256);

    function totalSupply() external view returns (uint256);
}
