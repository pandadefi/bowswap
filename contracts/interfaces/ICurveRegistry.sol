// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

interface ICurveRegistry {
    function get_pool_from_lp_token(address lp) external view returns (address);

    function get_lp_token(address pool) external view returns (address);

    function get_n_coins(address) external view returns (uint256[2] memory);

    function get_coins(address) external view returns (address[8] memory);
}
