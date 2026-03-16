// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DAOFactory} from "../src/DAOFactory.sol";
import {DAO} from "../src/DAO.sol";
import {DAOGovernanceToken} from "../src/DAOGovernanceToken.sol";
import {DAOTokenMarket} from "../src/DAOTokenMarket.sol";
import {TokenDeployer} from "../src/deployers/TokenDeployer.sol";
import {GovernorDeployer} from "../src/deployers/GovernorDeployer.sol";
import {GovernorPredictor} from "../src/deployers/GovernorPredictor.sol";
import {MarketDeployer} from "../src/deployers/MarketDeployer.sol";

contract DAOFlowTest is Test {
    DAOFactory internal factory;
    DAO internal dao;
    DAOGovernanceToken internal token;
    DAOTokenMarket internal market;

    address internal alice = address(0xA11CE);

    function setUp() public {
        TokenDeployer tokenDeployer = new TokenDeployer();
        GovernorPredictor governorPredictor = new GovernorPredictor(address(this));
        GovernorDeployer governorDeployer = new GovernorDeployer(address(governorPredictor));
        governorPredictor.transferOwnership(address(governorDeployer));
        MarketDeployer marketDeployer = new MarketDeployer();

        factory = new DAOFactory(
            address(this),
            address(tokenDeployer),
            address(governorDeployer),
            address(governorPredictor),
            address(marketDeployer)
        );

        uint256 id = factory.createDAO(
            "Flow DAO",
            "Flow Governance Token",
            "FLOW",
            20_000,
            0.0001 ether,
            0.00001 ether,
            4
        );
        DAOFactory.DAOInfo memory info = factory.getDAO(id);

        dao = DAO(payable(info.dao));
        token = DAOGovernanceToken(info.token);
        market = DAOTokenMarket(payable(info.market));
    }

    function testFullGovernanceFlow() public {
        vm.deal(alice, 10 ether);

        uint256 buyNonce = market.nonces(alice);
        uint256 buyDeadline = type(uint256).max;
        bytes32 buyActionHash = market.getBuyActionHash(1 ether, 1, buyNonce, buyDeadline);

        vm.prank(alice);
        bytes32 buyCommitHash = market.commit(buyActionHash);

        vm.warp(block.timestamp + market.REVEAL_DELAY() + 1);

        vm.prank(alice);
        uint256 bought = market.revealBuy{value: 1 ether}(1, buyNonce, buyDeadline, buyCommitHash);
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

    function testCommitRevealExpires() public {
        vm.deal(alice, 2 ether);

        uint256 buyNonce = market.nonces(alice);
        uint256 buyDeadline = type(uint256).max;
        bytes32 buyActionHash = market.getBuyActionHash(1 ether, 1, buyNonce, buyDeadline);

        vm.prank(alice);
        bytes32 buyCommitHash = market.commit(buyActionHash);

        vm.warp(block.timestamp + market.REVEAL_DELAY() + market.REVEAL_WINDOW() + 1);

        vm.prank(alice);
        vm.expectRevert("commit-expired");
        market.revealBuy{value: 1 ether}(1, buyNonce, buyDeadline, buyCommitHash);
    }

    function testRevealSellWithMismatchedHashReverts() public {
        vm.deal(alice, 5 ether);

        uint256 buyNonce = market.nonces(alice);
        uint256 buyDeadline = type(uint256).max;
        bytes32 buyActionHash = market.getBuyActionHash(1 ether, 1, buyNonce, buyDeadline);

        vm.prank(alice);
        bytes32 buyCommitHash = market.commit(buyActionHash);

        vm.warp(block.timestamp + market.REVEAL_DELAY() + 1);

        vm.prank(alice);
        market.revealBuy{value: 1 ether}(1, buyNonce, buyDeadline, buyCommitHash);

        vm.prank(alice);
        token.approve(address(market), type(uint256).max);

        uint256 sellNonce = market.nonces(alice);
        uint256 sellDeadline = type(uint256).max;
        bytes32 sellActionHash = market.getSellActionHash(1, 1, sellNonce, sellDeadline);

        vm.prank(alice);
        bytes32 sellCommitHash = market.commit(sellActionHash);

        vm.warp(block.timestamp + market.REVEAL_DELAY() + 1);

        vm.prank(alice);
        vm.expectRevert("commit-hash");
        market.revealSell(1, 2, sellNonce, sellDeadline, sellCommitHash);
    }
}
