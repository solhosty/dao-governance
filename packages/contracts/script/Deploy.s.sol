// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {DAOFactory} from "../src/DAOFactory.sol";
import {TokenDeployer} from "../src/deployers/TokenDeployer.sol";
import {GovernorDeployer} from "../src/deployers/GovernorDeployer.sol";
import {GovernorPredictor} from "../src/deployers/GovernorPredictor.sol";
import {MarketDeployer} from "../src/deployers/MarketDeployer.sol";

contract Deploy is Script {
    uint256 private constant MAX_RUNTIME_CODE_SIZE = 24_576;

    function run() external returns (DAOFactory factory) {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);

        vm.startBroadcast(deployerPk);

        TokenDeployer tokenDeployer = new TokenDeployer(deployer);
        GovernorPredictor governorPredictor = new GovernorPredictor(deployer);
        GovernorDeployer governorDeployer = new GovernorDeployer(deployer, address(governorPredictor));
        MarketDeployer marketDeployer = new MarketDeployer(deployer);

        require(address(tokenDeployer).code.length <= MAX_RUNTIME_CODE_SIZE, "token-deployer-code-too-large");
        require(address(governorDeployer).code.length <= MAX_RUNTIME_CODE_SIZE, "governor-deployer-code-too-large");
        require(
            address(governorPredictor).code.length <= MAX_RUNTIME_CODE_SIZE,
            "governor-predictor-code-too-large"
        );
        require(address(marketDeployer).code.length <= MAX_RUNTIME_CODE_SIZE, "market-deployer-code-too-large");

        factory = new DAOFactory(
            deployer,
            address(tokenDeployer),
            address(governorDeployer),
            address(governorPredictor),
            address(marketDeployer)
        );
        require(address(factory).code.length <= MAX_RUNTIME_CODE_SIZE, "factory-code-too-large");

        tokenDeployer.transferOwnership(address(factory));
        governorDeployer.transferOwnership(address(factory));
        marketDeployer.transferOwnership(address(factory));
        governorPredictor.transferOwnership(address(governorDeployer));

        vm.stopBroadcast();
    }
}
