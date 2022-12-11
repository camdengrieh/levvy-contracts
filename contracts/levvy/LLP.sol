// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../tokens/MintableBaseToken.sol";

contract LLP is MintableBaseToken {
    constructor() public MintableBaseToken("LEV LP", "LLP", 0) {}

    function id() external pure returns (string memory _name) {
        return "LLP";
    }
}
