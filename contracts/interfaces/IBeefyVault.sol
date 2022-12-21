// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface IBeefyVault {
    function want() external view returns (address);

    function balanceOf(address owner) external view returns (uint256);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function transferFrom(
        address owner,
        address recipient,
        uint256 amount
    ) external;

    function withdrawAll() external;

    function getPricePerFullShare() external view returns (uint256);
}
