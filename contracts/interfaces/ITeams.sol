pragma solidity ^0.8.0;
pragma abicoder v2;

// SPDX-License-Identifier: MIT

/**
 * PowerBull (https://powerbull.net)
 * @author PowerBull <hello@powerbull.net>
 */

abstract contract ITeams {

    function logTransferTx(
        bytes32 txType,
        address msgSender__,
        address sender,
        address recipient,
        uint256 amount,
        uint256 amountWithFee
    ) virtual public returns(uint256);


}