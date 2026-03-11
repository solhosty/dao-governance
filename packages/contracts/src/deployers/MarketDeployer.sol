// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DAOGovernanceToken} from "../DAOGovernanceToken.sol";
import {DAOTokenMarket} from "../DAOTokenMarket.sol";

contract MarketDeployer {
    function deploy(
        bytes32 salt,
        DAOGovernanceToken token,
        address initialOwner,
        uint256 basePriceWei,
        uint256 slopeWei
    ) external returns (address market) {
        market = address(new DAOTokenMarket{salt: salt}(token, initialOwner, basePriceWei, slopeWei));
    }

    function predict(
        bytes32 salt,
        DAOGovernanceToken token,
        address initialOwner,
        uint256 basePriceWei,
        uint256 slopeWei
    ) external view returns (address predicted) {
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(
                type(DAOTokenMarket).creationCode,
                abi.encode(token, initialOwner, basePriceWei, slopeWei)
            )
        );

        predicted = _computeCreate2Address(salt, initCodeHash);
    }

    function _computeCreate2Address(bytes32 salt, bytes32 initCodeHash) private view returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initCodeHash)))));
    }
}
