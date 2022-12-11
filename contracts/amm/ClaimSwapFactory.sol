// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./interfaces/IClaimSwapFactory.sol";

contract ClaimSwapFactory is IClaimSwapFactory {
    address public btc;
    address public klay;
    address public dai;

    address public klayBusdPair;
    address public btcBnbPair;

    constructor(address[] memory _addresses) public {
        btc = _addresses[0];
        klay = _addresses[1];
        dai = _addresses[2];

        klayBusdPair = _addresses[3];
        btcBnbPair = _addresses[4];
    }

    function getPair(address tokenA, address tokenB) external view override returns (address) {
        if (tokenA == dai && tokenB == klay) {
            return klayBusdPair;
        }
        if (tokenA == klay && tokenB == btc) {
            return btcBnbPair;
        }
        revert("Invalid tokens");
    }
}
