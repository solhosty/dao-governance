// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {DAOFactory} from "../src/DAOFactory.sol";
import {TokenDeployer} from "../src/deployers/TokenDeployer.sol";
import {GovernorDeployer} from "../src/deployers/GovernorDeployer.sol";
import {MarketDeployer} from "../src/deployers/MarketDeployer.sol";

contract Deploy is Script {
    uint256 private constant MAX_RUNTIME_CODE_SIZE = 24_576;

    function run() external returns (DAOFactory factory) {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPk);

        TokenDeployer tokenDeployer = new TokenDeployer();
        GovernorDeployer governorDeployer = new GovernorDeployer();
        MarketDeployer marketDeployer = new MarketDeployer();

        factory = new DAOFactory(
            vm.addr(deployerPk),
            address(tokenDeployer),
            address(governorDeployer),
            address(marketDeployer)
        );
        require(address(factory).code.length <= MAX_RUNTIME_CODE_SIZE, "factory-code-too-large");

        vm.stopBroadcast();
    }
}
