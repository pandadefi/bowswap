// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

interface ICurveFactoryRegistry {
    function get_coins(address) external view returns (address[4] memory);

    function get_n_coins(address) external view returns (uint256);
}
