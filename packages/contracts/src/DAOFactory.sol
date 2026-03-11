// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
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

        DAOGovernanceToken token = new DAOGovernanceToken(name, symbol, address(this), initialSupply);
        if (initialSupply > 0) {
            token.transfer(msg.sender, initialSupply * token.TOKEN_UNIT());
        }

        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](0);
        TimelockController timelock = new TimelockController(
            DEFAULT_TIMELOCK_DELAY,
            proposers,
            executors,
            address(this)
        );

        DAO dao = new DAO(
            string.concat(name, " Governor"),
            token,
            timelock,
            DEFAULT_VOTING_DELAY,
            DEFAULT_VOTING_PERIOD,
            quorumNumerator
        );

        DAOTokenMarket market = new DAOTokenMarket(token, address(timelock), basePriceWei, slopeWei);

        token.transferOwnership(address(market));

        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 cancellerRole = timelock.CANCELLER_ROLE();
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();

        timelock.grantRole(proposerRole, address(dao));
        timelock.grantRole(cancellerRole, address(dao));
        timelock.grantRole(executorRole, address(0));
        timelock.revokeRole(adminRole, address(this));

        daoId = daos.length;
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
}
