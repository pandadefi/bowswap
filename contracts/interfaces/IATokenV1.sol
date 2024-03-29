// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface IATokenV1 {
    function underlyingAssetAddress() external view returns (address);

    function redeem(uint256 _amount) external;
}
