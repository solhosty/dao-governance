// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DAOGovernanceToken} from "../DAOGovernanceToken.sol";

contract TokenDeployer {
    function deploy(
        bytes32 salt,
        string memory name,
        string memory symbol,
        address initialOwner,
        uint256 initialSupply
    ) external returns (address token) {
        token = address(new DAOGovernanceToken{salt: salt}(name, symbol, initialOwner, initialSupply));
    }

    function predict(
        bytes32 salt,
        string memory name,
        string memory symbol,
        address initialOwner,
        uint256 initialSupply
    ) external view returns (address predicted) {
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(
                type(DAOGovernanceToken).creationCode,
                abi.encode(name, symbol, initialOwner, initialSupply)
            )
        );

        predicted = _computeCreate2Address(salt, initCodeHash);
    }

    function _computeCreate2Address(bytes32 salt, bytes32 initCodeHash) private view returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initCodeHash)))));
    }
}
