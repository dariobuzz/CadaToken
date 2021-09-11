// SPDX-License-Identifier: MIT

/**
 * PowerBull (https://powerbull.net)
 * @author PowerBull <hello@powerbull.net>
 */
 
pragma solidity ^0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IHoldlersRewardComputer.sol";
import "./interfaces/ICada.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./StructsDef.sol";
import "hardhat/console.sol";
import "./Commons.sol";

contract Teams {

    mapping(uint256 => StructsDef.FactionInfo) public factionsData;
    mapping(address => uint256) public factionsDataIndexes;

    function logTransferTx(
        bytes32 txType,
        address msgSender__,
        address sender,
        address recipient,
        uint256 amount,
        uint256 amountWithFee
    ) public {
        //todo
    }

}