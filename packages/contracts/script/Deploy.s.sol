// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {DAOFactory} from "../src/DAOFactory.sol";

contract Deploy is Script {
    function run() external returns (DAOFactory factory) {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPk);

        factory = new DAOFactory(vm.addr(deployerPk));

        vm.stopBroadcast();
    }
}
