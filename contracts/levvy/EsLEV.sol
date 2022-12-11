// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../tokens/MintableBaseToken.sol";

contract EsLEV is MintableBaseToken {
    constructor() public MintableBaseToken("Escrowed LEV", "esLEV", 0) {}

    function id() external pure returns (string memory _name) {
        return "esLEV";
    }
}
