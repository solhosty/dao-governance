// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {DAO} from "../DAO.sol";
import {GovernorPredictor} from "./GovernorPredictor.sol";

contract GovernorDeployer {
    GovernorPredictor public immutable governorPredictor;

    constructor(address governorPredictor_) {
        require(governorPredictor_ != address(0), "governor-predictor=0");
        governorPredictor = GovernorPredictor(governorPredictor_);
    }

    function deploy(
        bytes32 timelockSalt,
        bytes32 daoSalt,
        string memory governorName,
        IVotes token,
        uint48 votingDelaySeconds,
        uint32 votingPeriodSeconds,
        uint256 quorumNumerator,
        address timelockAdmin
    ) external returns (address dao, address timelock) {
        timelock = governorPredictor.deployTimelock(timelockSalt, timelockAdmin);

        DAO deployedDAO = new DAO{salt: daoSalt}(
            governorName,
            token,
            TimelockController(payable(timelock)),
            votingDelaySeconds,
            votingPeriodSeconds,
            quorumNumerator
        );

        dao = address(deployedDAO);
    }

    function predictDAO(
        bytes32 daoSalt,
        string memory governorName,
        IVotes token,
        address timelock,
        uint48 votingDelaySeconds,
        uint32 votingPeriodSeconds,
        uint256 quorumNumerator
    ) external view returns (address dao) {
        bytes32 daoInitCodeHash = keccak256(
            abi.encodePacked(
                type(DAO).creationCode,
                abi.encode(
                    governorName,
                    token,
                    TimelockController(payable(timelock)),
                    votingDelaySeconds,
                    votingPeriodSeconds,
                    quorumNumerator
                )
            )
        );
        dao = _computeCreate2Address(daoSalt, daoInitCodeHash);
    }

    function _computeCreate2Address(bytes32 salt, bytes32 initCodeHash) private view returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initCodeHash)))));
    }
}
