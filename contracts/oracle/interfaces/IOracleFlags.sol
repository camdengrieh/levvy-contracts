// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IOracleFlags {
  function getFlag(address) external view returns (bool);
}
