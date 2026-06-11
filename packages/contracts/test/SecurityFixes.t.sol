// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DAOFactory} from "../src/DAOFactory.sol";
import {DAOGovernanceToken} from "../src/DAOGovernanceToken.sol";
import {DAOTokenMarket} from "../src/DAOTokenMarket.sol";
import {TokenDeployer} from "../src/deployers/TokenDeployer.sol";
import {GovernorDeployer} from "../src/deployers/GovernorDeployer.sol";
import {GovernorPredictor} from "../src/deployers/GovernorPredictor.sol";
import {MarketDeployer} from "../src/deployers/MarketDeployer.sol";

contract SecurityFixesTest is Test {
    DAOFactory internal factory;
    DAOGovernanceToken internal token;
    DAOTokenMarket internal market;

    address internal alice = address(0xA11CE);

    function setUp() public {
        TokenDeployer tokenDeployer = new TokenDeployer();
        GovernorPredictor governorPredictor = new GovernorPredictor();
        GovernorDeployer governorDeployer = new GovernorDeployer(address(governorPredictor));
        MarketDeployer marketDeployer = new MarketDeployer();

        factory = new DAOFactory(
            address(this),
            address(tokenDeployer),
            address(governorDeployer),
            address(governorPredictor),
            address(marketDeployer)
        );

        uint256 id = factory.createDAO(
            "Security DAO",
            "Security Governance Token",
            "SAFE",
            20_000,
            0.0001 ether,
            0.00001 ether,
            4
        );
        DAOFactory.DAOInfo memory info = factory.getDAO(id);

        token = DAOGovernanceToken(info.token);
        market = DAOTokenMarket(payable(info.market));
    }

    function testDonationDoesNotAffectCirculatingSupply() public {
        uint256 supplyBefore = market.circulatingSupplyTokens();
        uint256 quoteBefore = market.quoteBuy(1 ether);

        bool donated = token.transfer(address(market), 250 * token.TOKEN_UNIT());
        assertTrue(donated);

        uint256 supplyAfter = market.circulatingSupplyTokens();
        uint256 quoteAfter = market.quoteBuy(1 ether);

        assertEq(supplyAfter, supplyBefore);
        assertEq(quoteAfter, quoteBefore);
    }

    function testSellBurnsTokensAndUpdatesTrackedSupply() public {
        vm.deal(alice, 10 ether);

        vm.prank(alice);
        uint256 bought = market.buy{value: 1 ether}(1);
        assertGt(bought, 0);

        uint256 sellTokens = bought / 2;
        if (sellTokens == 0) {
            sellTokens = 1;
        }

        uint256 supplyBefore = market.circulatingSupplyTokens();
        uint256 totalSupplyBefore = token.totalSupply();

        vm.startPrank(alice);
        token.approve(address(market), sellTokens * token.TOKEN_UNIT());
        uint256 ethOut = market.sell(sellTokens, 0);
        vm.stopPrank();

        assertGt(ethOut, 0);
        assertEq(token.balanceOf(address(market)), 0);
        assertEq(market.circulatingSupplyTokens(), supplyBefore - sellTokens);
        assertEq(token.totalSupply(), totalSupplyBefore - (sellTokens * token.TOKEN_UNIT()));
    }
}
