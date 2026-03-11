// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DAOFactory} from "../src/DAOFactory.sol";
import {DAO} from "../src/DAO.sol";
import {DAOGovernanceToken} from "../src/DAOGovernanceToken.sol";
import {DAOTokenMarket} from "../src/DAOTokenMarket.sol";
import {TokenDeployer} from "../src/deployers/TokenDeployer.sol";
import {GovernorDeployer} from "../src/deployers/GovernorDeployer.sol";
import {MarketDeployer} from "../src/deployers/MarketDeployer.sol";

contract DAOFlowTest is Test {
    DAOFactory internal factory;
    DAO internal dao;
    DAOGovernanceToken internal token;
    DAOTokenMarket internal market;

    address internal alice = address(0xA11CE);

    function setUp() public {
        TokenDeployer tokenDeployer = new TokenDeployer();
        GovernorDeployer governorDeployer = new GovernorDeployer();
        MarketDeployer marketDeployer = new MarketDeployer();

        factory = new DAOFactory(
            address(this),
            address(tokenDeployer),
            address(governorDeployer),
            address(marketDeployer)
        );

        uint256 id = factory.createDAO("Flow DAO", "FLOW", 20_000, 0.0001 ether, 0.00001 ether, 4);
        DAOFactory.DAOInfo memory info = factory.getDAO(id);

        dao = DAO(payable(info.dao));
        token = DAOGovernanceToken(info.token);
        market = DAOTokenMarket(payable(info.market));
    }

    function testFullGovernanceFlow() public {
        vm.deal(alice, 10 ether);

        vm.prank(alice);
        uint256 bought = market.buy{value: 1 ether}(1);
        assertGt(bought, 0);

        token.delegate(address(this));
        vm.prank(alice);
        token.delegate(alice);

        uint256 newBase = 0.0002 ether;
        uint256 newSlope = 0.00002 ether;
        bytes memory callData = abi.encodeCall(DAOTokenMarket.setCurveParams, (newBase, newSlope));

        address[] memory targets = new address[](1);
        targets[0] = address(market);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = callData;

        string memory description = "Adjust bonding curve parameters";
        uint256 proposalId = dao.propose(targets, values, calldatas, description);

        vm.warp(block.timestamp + dao.votingDelay() + 1);

        dao.castVote(proposalId, 1);
        vm.prank(alice);
        dao.castVote(proposalId, 1);

        vm.warp(block.timestamp + dao.votingPeriod() + 1);

        bytes32 descriptionHash = keccak256(bytes(description));
        dao.queue(targets, values, calldatas, descriptionHash);

        vm.warp(block.timestamp + 1 hours + 1);
        dao.execute(targets, values, calldatas, descriptionHash);

        assertEq(market.basePriceWei(), newBase);
        assertEq(market.slopeWei(), newSlope);
    }
}
