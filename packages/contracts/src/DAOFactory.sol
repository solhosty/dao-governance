// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {DAOGovernanceToken} from "./DAOGovernanceToken.sol";
import {DAO} from "./DAO.sol";
import {DAOTokenMarket} from "./DAOTokenMarket.sol";

contract DAOFactory is Ownable {
    struct DAOInfo {
        uint256 id;
        string name;
        string symbol;
        address creator;
        address token;
        address dao;
        address market;
        address timelock;
        uint256 createdAt;
    }

    uint48 public constant DEFAULT_VOTING_DELAY = 1 hours;
    uint32 public constant DEFAULT_VOTING_PERIOD = 1 days;
    uint256 public constant DEFAULT_TIMELOCK_DELAY = 1 hours;

    DAOInfo[] private daos;

    event DAOCreated(
        uint256 indexed daoId,
        address indexed creator,
        address token,
        address dao,
        address market,
        address timelock
    );

    struct PredictedAddresses {
        address token;
        address dao;
        address market;
        address timelock;
    }

    constructor(address owner_) Ownable(owner_) {}

    function createDAO(
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        uint256 basePriceWei,
        uint256 slopeWei,
        uint256 quorumNumerator
    ) external returns (uint256 daoId) {
        require(bytes(name).length > 0, "name-empty");
        require(bytes(symbol).length > 0, "symbol-empty");
        require(quorumNumerator > 0 && quorumNumerator <= 100, "bad-quorum");

        daoId = daos.length;
        bytes32 deploymentSalt = _deploymentSalt(msg.sender, name, symbol, daoId);

        bytes32 tokenSalt = _typedSalt(deploymentSalt, "TOKEN");
        bytes32 timelockSalt = _typedSalt(deploymentSalt, "TIMELOCK");
        bytes32 daoSalt = _typedSalt(deploymentSalt, "GOVERNOR");
        bytes32 marketSalt = _typedSalt(deploymentSalt, "MARKET");

        DAOGovernanceToken token = new DAOGovernanceToken{salt: tokenSalt}(
            name,
            symbol,
            address(this),
            initialSupply
        );

        if (initialSupply > 0) {
            token.transfer(msg.sender, initialSupply * token.TOKEN_UNIT());
        }

        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](0);
        TimelockController timelock = new TimelockController{salt: timelockSalt}(
            DEFAULT_TIMELOCK_DELAY,
            proposers,
            executors,
            address(this)
        );

        DAO dao = new DAO{salt: daoSalt}(
            string.concat(name, " Governor"),
            token,
            timelock,
            DEFAULT_VOTING_DELAY,
            DEFAULT_VOTING_PERIOD,
            quorumNumerator
        );

        DAOTokenMarket market = new DAOTokenMarket{salt: marketSalt}(
            token,
            address(timelock),
            basePriceWei,
            slopeWei
        );

        token.transferOwnership(address(market));

        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 cancellerRole = timelock.CANCELLER_ROLE();
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();

        timelock.grantRole(proposerRole, address(dao));
        timelock.grantRole(cancellerRole, address(dao));
        timelock.grantRole(executorRole, address(0));
        timelock.revokeRole(adminRole, address(this));

        daos.push(
            DAOInfo({
                id: daoId,
                name: name,
                symbol: symbol,
                creator: msg.sender,
                token: address(token),
                dao: address(dao),
                market: address(market),
                timelock: address(timelock),
                createdAt: block.timestamp
            })
        );

        emit DAOCreated(
            daoId,
            msg.sender,
            address(token),
            address(dao),
            address(market),
            address(timelock)
        );
    }

    function predictAddresses(
        address creator,
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        uint256 basePriceWei,
        uint256 slopeWei,
        uint256 quorumNumerator
    ) external view returns (PredictedAddresses memory predicted) {
        uint256 daoId = daos.length;
        bytes32 deploymentSalt = _deploymentSalt(creator, name, symbol, daoId);

        bytes32 tokenSalt = _typedSalt(deploymentSalt, "TOKEN");
        bytes32 timelockSalt = _typedSalt(deploymentSalt, "TIMELOCK");
        bytes32 daoSalt = _typedSalt(deploymentSalt, "GOVERNOR");
        bytes32 marketSalt = _typedSalt(deploymentSalt, "MARKET");

        predicted.token = _computeCreate2Address(
            tokenSalt,
            keccak256(
                abi.encodePacked(
                    type(DAOGovernanceToken).creationCode,
                    abi.encode(name, symbol, address(this), initialSupply)
                )
            )
        );

        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](0);
        predicted.timelock = _computeCreate2Address(
            timelockSalt,
            keccak256(
                abi.encodePacked(
                    type(TimelockController).creationCode,
                    abi.encode(DEFAULT_TIMELOCK_DELAY, proposers, executors, address(this))
                )
            )
        );

        predicted.dao = _computeCreate2Address(
            daoSalt,
            keccak256(
                abi.encodePacked(
                    type(DAO).creationCode,
                    abi.encode(
                        string.concat(name, " Governor"),
                        IVotes(predicted.token),
                        TimelockController(payable(predicted.timelock)),
                        DEFAULT_VOTING_DELAY,
                        DEFAULT_VOTING_PERIOD,
                        quorumNumerator
                    )
                )
            )
        );

        predicted.market = _computeCreate2Address(
            marketSalt,
            keccak256(
                abi.encodePacked(
                    type(DAOTokenMarket).creationCode,
                    abi.encode(
                        DAOGovernanceToken(predicted.token),
                        predicted.timelock,
                        basePriceWei,
                        slopeWei
                    )
                )
            )
        );
    }

    function totalDAOs() external view returns (uint256) {
        return daos.length;
    }

    function getDAO(uint256 daoId) external view returns (DAOInfo memory) {
        require(daoId < daos.length, "dao-not-found");
        return daos[daoId];
    }

    function listDAOs(uint256 offset, uint256 limit) external view returns (DAOInfo[] memory items) {
        if (offset >= daos.length) {
            return new DAOInfo[](0);
        }

        uint256 end = offset + limit;
        if (end > daos.length) {
            end = daos.length;
        }

        items = new DAOInfo[](end - offset);
        uint256 idx = 0;
        for (uint256 i = offset; i < end; i++) {
            items[idx] = daos[i];
            idx++;
        }
    }

    function _deploymentSalt(
        address creator,
        string memory name,
        string memory symbol,
        uint256 daoId
    ) private pure returns (bytes32) {
        return keccak256(abi.encode(creator, name, symbol, daoId));
    }

    function _typedSalt(bytes32 deploymentSalt, string memory kind) private pure returns (bytes32) {
        return keccak256(abi.encode(deploymentSalt, kind));
    }

    function _computeCreate2Address(bytes32 salt, bytes32 initCodeHash) private view returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initCodeHash)))));
    }
}
