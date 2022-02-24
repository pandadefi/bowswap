// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

interface ILendingPool {
    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external;
}
