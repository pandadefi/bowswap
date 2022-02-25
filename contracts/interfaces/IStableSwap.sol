// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

interface IStableSwap {
    function remove_liquidity_one_coin(
        uint256 amount,
        int128 i,
        uint256 min_amount
    ) external;

    function add_liquidity(uint256[2] calldata amounts, uint256 min_mint_amount)
        external;

    function add_liquidity(uint256[3] calldata amounts, uint256 min_mint_amount)
        external;

    function add_liquidity(uint256[4] calldata amounts, uint256 min_mint_amount)
        external;

    function calc_withdraw_one_coin(uint256 _token_amount, int128 i)
        external
        view
        returns (uint256);

    function calc_token_amount(uint256[2] calldata amounts, bool is_deposit)
        external
        view
        returns (uint256);

    function calc_token_amount(uint256[2] calldata amounts)
        external
        view
        returns (uint256);

    function calc_token_amount(uint256[3] calldata amounts, bool is_deposit)
        external
        view
        returns (uint256);

    function calc_token_amount(uint256[3] calldata amounts)
        external
        view
        returns (uint256);

    function calc_token_amount(uint256[4] calldata amounts, bool is_deposit)
        external
        view
        returns (uint256);

    function calc_token_amount(uint256[4] calldata amounts)
        external
        view
        returns (uint256);
}
