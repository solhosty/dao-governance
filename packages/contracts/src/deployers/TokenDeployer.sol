// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DAOGovernanceToken} from "../DAOGovernanceToken.sol";

contract TokenDeployer {
    /// @notice Deploys a token with a caller-bound CREATE2 salt to prevent front-running.
    function deploy(
        bytes32 salt,
        string memory name,
        string memory symbol,
        address initialOwner,
        uint256 initialSupply
    ) external returns (address token) {
        bytes32 effectiveSalt = _deriveEffectiveSalt(msg.sender, salt);
        token = address(new DAOGovernanceToken{salt: effectiveSalt}(name, symbol, initialOwner, initialSupply));
    }

    /// @notice Predicts the deployment address for the caller using caller-bound salt derivation.
    function predict(
        bytes32 salt,
        string memory name,
        string memory symbol,
        address initialOwner,
        uint256 initialSupply
    ) external view returns (address predicted) {
        return predictFor(msg.sender, salt, name, symbol, initialOwner, initialSupply);
    }

    /// @notice Predicts the deployment address for a specific deployer address.
    function predictFor(
        address deployer,
        bytes32 salt,
        string memory name,
        string memory symbol,
        address initialOwner,
        uint256 initialSupply
    ) public view returns (address predicted) {
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(
                type(DAOGovernanceToken).creationCode,
                abi.encode(name, symbol, initialOwner, initialSupply)
            )
        );

        bytes32 effectiveSalt = _deriveEffectiveSalt(deployer, salt);
        predicted = _computeCreate2Address(effectiveSalt, initCodeHash);
    }

    function _deriveEffectiveSalt(address deployer, bytes32 salt) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(deployer, salt));
    }

    function _computeCreate2Address(bytes32 salt, bytes32 initCodeHash) private view returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initCodeHash)))));
    }
}
