// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../tokens/MintableBaseToken.sol";

contract LEV is MintableBaseToken {
    constructor() public MintableBaseToken("LEV", "LEV", 0) {}

    function id() external pure returns (string memory _name) {
        return "LEV";
    }
}
