// SPDX-License-Identifier:  GPLv3
pragma solidity ^0.8.4;

interface IUniswapV2Migrator {
    function migrate(address token, uint amountTokenMin, uint amountETHMin, address to, uint deadline) external;
}
