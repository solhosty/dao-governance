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

        vm.startBroadcast(deployerPk);
        try this._runInternal(deployerPk) returns (DAOFactory deployedFactory) {
            factory = deployedFactory;
            vm.stopBroadcast();
        } catch {
            vm.stopBroadcast();
            revert("deployment-failed");
        }
    }

    function _runInternal(uint256 deployerPk) external returns (DAOFactory factory) {
        require(msg.sender == address(this), "only-self");

        TokenDeployer tokenDeployer = new TokenDeployer();
        GovernorPredictor governorPredictor = new GovernorPredictor(vm.addr(deployerPk));
        GovernorDeployer governorDeployer = new GovernorDeployer(address(governorPredictor));
        governorPredictor.transferOwnership(address(governorDeployer));
        MarketDeployer marketDeployer = new MarketDeployer();

        require(address(tokenDeployer).code.length <= MAX_RUNTIME_CODE_SIZE, "token-deployer-code-too-large");
        require(address(governorDeployer).code.length <= MAX_RUNTIME_CODE_SIZE, "governor-deployer-code-too-large");
        require(
            address(governorPredictor).code.length <= MAX_RUNTIME_CODE_SIZE,
            "governor-predictor-code-too-large"
        );
        require(address(marketDeployer).code.length <= MAX_RUNTIME_CODE_SIZE, "market-deployer-code-too-large");

        factory = new DAOFactory(
            vm.addr(deployerPk),
            address(tokenDeployer),
            address(governorDeployer),
            address(governorPredictor),
            address(marketDeployer)
        );
        require(address(factory).code.length <= MAX_RUNTIME_CODE_SIZE, "factory-code-too-large");
    }
}
