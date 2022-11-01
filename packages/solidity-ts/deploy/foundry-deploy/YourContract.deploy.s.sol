// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import { GameFactory } from "contracts/GameFactory.sol";

contract YourContractDeploy is Script {
  function setUp() public {}

  function run() public {
    vm.startBroadcast();
    new GameFactory(2353);
    vm.stopBroadcast();
  }
}
