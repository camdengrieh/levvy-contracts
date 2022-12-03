// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

contract KspFactory {
    mapping(address => mapping(address => mapping(uint24 => address))) public getPool;
}
