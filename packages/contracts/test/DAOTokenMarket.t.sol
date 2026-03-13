// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DAOGovernanceToken} from "../src/DAOGovernanceToken.sol";
import {DAOTokenMarket} from "../src/DAOTokenMarket.sol";

contract MockPriceOracle {
    uint256 public currentPriceWei;

    function setPriceWei(uint256 newPriceWei) external {
        currentPriceWei = newPriceWei;
    }

    function priceWei() external view returns (uint256) {
        return currentPriceWei;
    }
}

contract DAOTokenMarketTest is Test {
    DAOGovernanceToken internal token;
    DAOTokenMarket internal market;
    MockPriceOracle internal oracle;

    address internal bob = address(0xB0B);

    function setUp() public {
        token = new DAOGovernanceToken("DAO Token", "DAO", address(this), 1_000);
        market = new DAOTokenMarket(token, address(this), 0.001 ether, 0.0001 ether);
        oracle = new MockPriceOracle();
    }

    function testQuoteUsesOracleWhenConfigured() public {
        oracle.setPriceWei(0.02 ether);
        market.setPriceOracle(address(oracle));

        assertEq(market.quoteBuy(1 ether), 50);
        assertEq(market.quoteSell(7), 0.14 ether);
    }

    function testQuoteFallsBackToCurveWhenOracleUnset() public view {
        uint256 supply = market.circulatingSupplyTokens();

        uint256 ethAmount = 2 ether;
        uint256 quotedTokens = market.quoteBuy(ethAmount);
        uint256 buyCost = market.costForTokens(supply, quotedTokens);
        uint256 nextBuyCost = market.costForTokens(supply, quotedTokens + 1);

        assertLe(buyCost, ethAmount);
        assertGt(nextBuyCost, ethAmount);

        uint256 tokensToSell = 5;
        uint256 expectedProceeds = market.proceedsForTokens(supply, tokensToSell);
        assertEq(market.quoteSell(tokensToSell), expectedProceeds);
    }

    function testOnlyOwnerCanSetOracle() public {
        vm.prank(bob);
        vm.expectRevert();
        market.setPriceOracle(address(oracle));
    }

    function testOraclePriceUpdatesAffectQuotesImmediately() public {
        market.setPriceOracle(address(oracle));

        oracle.setPriceWei(0.01 ether);
        assertEq(market.quoteBuy(1 ether), 100);
        assertEq(market.quoteSell(3), 0.03 ether);

        oracle.setPriceWei(0.025 ether);
        assertEq(market.quoteBuy(1 ether), 40);
        assertEq(market.quoteSell(3), 0.075 ether);
    }
}
