// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

contract GovernorPredictor is Ownable {
    constructor(address initialOwner) Ownable(initialOwner) {}

    function deployTimelock(
        bytes32 timelockSalt,
        address timelockAdmin
    ) external onlyOwner returns (address timelock) {
        require(timelockAdmin != address(0), "admin=0");

        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](0);

        timelock = address(new TimelockController{salt: timelockSalt}(1 hours, proposers, executors, timelockAdmin));
    }

    function predictTimelock(
        address deployer,
        bytes32 timelockSalt,
        address timelockAdmin
    ) external pure returns (address timelock) {
        require(deployer != address(0), "deployer=0");
        require(timelockAdmin != address(0), "admin=0");

        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](0);

        bytes32 timelockInitCodeHash = keccak256(
            abi.encodePacked(
                type(TimelockController).creationCode,
                abi.encode(1 hours, proposers, executors, timelockAdmin)
            )
        );
        timelock = _computeCreate2Address(deployer, timelockSalt, timelockInitCodeHash);
    }

    function _computeCreate2Address(
        address deployer,
        bytes32 salt,
        bytes32 initCodeHash
    ) private pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, initCodeHash)))));
    }
}
