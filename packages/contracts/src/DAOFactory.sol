// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {DAOGovernanceToken} from "./DAOGovernanceToken.sol";
import {TokenDeployer} from "./deployers/TokenDeployer.sol";
import {GovernorDeployer} from "./deployers/GovernorDeployer.sol";
import {GovernorPredictor} from "./deployers/GovernorPredictor.sol";
import {MarketDeployer} from "./deployers/MarketDeployer.sol";

contract DAOFactory is Ownable {
    uint256 private constant TOKEN_UNIT = 1e18;

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

    TokenDeployer public immutable tokenDeployer;
    GovernorDeployer public immutable governorDeployer;
    GovernorPredictor public immutable governorPredictor;
    MarketDeployer public immutable marketDeployer;

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

    constructor(
        address owner_,
        address tokenDeployer_,
        address governorDeployer_,
        address governorPredictor_,
        address marketDeployer_
    ) Ownable(owner_) {
        require(tokenDeployer_ != address(0), "token-deployer=0");
        require(governorDeployer_ != address(0), "governor-deployer=0");
        require(governorPredictor_ != address(0), "governor-predictor=0");
        require(marketDeployer_ != address(0), "market-deployer=0");

        tokenDeployer = TokenDeployer(tokenDeployer_);
        governorDeployer = GovernorDeployer(governorDeployer_);
        governorPredictor = GovernorPredictor(governorPredictor_);
        marketDeployer = MarketDeployer(marketDeployer_);
    }

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

        address tokenAddress = tokenDeployer.deploy(tokenSalt, name, symbol, address(this), initialSupply);
        DAOGovernanceToken token = DAOGovernanceToken(tokenAddress);

        if (initialSupply > 0) {
            require(token.transfer(msg.sender, initialSupply * TOKEN_UNIT), "initial-transfer-failed");
        }

        (address daoAddress, address timelockAddress) = governorDeployer.deploy(
            timelockSalt,
            daoSalt,
            string.concat(name, " Governor"),
            IVotes(tokenAddress),
            DEFAULT_VOTING_DELAY,
            DEFAULT_VOTING_PERIOD,
            quorumNumerator,
            address(this)
        );

        TimelockController timelock = TimelockController(payable(timelockAddress));

        address marketAddress = marketDeployer.deploy(
            marketSalt,
            token,
            timelockAddress,
            basePriceWei,
            slopeWei
        );

        token.transferOwnership(marketAddress);

        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 cancellerRole = timelock.CANCELLER_ROLE();
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();

        timelock.grantRole(proposerRole, daoAddress);
        timelock.grantRole(cancellerRole, daoAddress);
        timelock.grantRole(executorRole, address(0));
        timelock.revokeRole(adminRole, address(this));

        daos.push(
            DAOInfo({
                id: daoId,
                name: name,
                symbol: symbol,
                creator: msg.sender,
                token: tokenAddress,
                dao: daoAddress,
                market: marketAddress,
                timelock: timelockAddress,
                createdAt: block.timestamp
            })
        );

        emit DAOCreated(daoId, msg.sender, tokenAddress, daoAddress, marketAddress, timelockAddress);
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

        predicted.token = tokenDeployer.predict(
            tokenSalt,
            name,
            symbol,
            address(this),
            initialSupply
        );

        predicted.timelock = governorPredictor.predictTimelock(
            address(governorPredictor),
            timelockSalt,
            address(this)
        );

        predicted.dao = governorDeployer.predictDAO(
            daoSalt,
            string.concat(name, " Governor"),
            IVotes(predicted.token),
            predicted.timelock,
            DEFAULT_VOTING_DELAY,
            DEFAULT_VOTING_PERIOD,
            quorumNumerator
        );

        predicted.market = marketDeployer.predict(
            marketSalt,
            DAOGovernanceToken(predicted.token),
            predicted.timelock,
            basePriceWei,
            slopeWei
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

}
