// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

interface IYearnRegistry {
    function latestVault(address) external view returns (address);
}
