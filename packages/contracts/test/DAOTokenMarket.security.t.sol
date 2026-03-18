// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DAOGovernanceToken} from "../src/DAOGovernanceToken.sol";
import {DAOTokenMarket} from "../src/DAOTokenMarket.sol";

contract DAOTokenMarketSecurityTest is Test {
    uint256 internal constant TOKEN_UNIT = 1e18;

    DAOGovernanceToken internal token;
    DAOTokenMarket internal market;

    address internal alice = address(0xA11CE);

    function setUp() public {
        token = new DAOGovernanceToken("Security DAO Token", "SDT", address(this), 0);
        market = new DAOTokenMarket(token, address(this), 0.0001 ether, 0.00001 ether);
        token.transferOwnership(address(market));
    }

    function testCommitRevealBuyAndSellHappyPath() public {
        vm.deal(alice, 10 ether);

        uint256 bought = _commitAndRevealBuy(alice, 1 ether, 1, keccak256("buy-happy"));
        assertGt(bought, 0);

        uint256 sellAmount = bought / 2;
        assertGt(sellAmount, 0);

        vm.prank(alice);
        token.approve(address(market), sellAmount * TOKEN_UNIT);

        bytes32 sellSalt = keccak256("sell-happy");
        bytes32 sellHash = keccak256(abi.encode("SELL", alice, sellAmount, uint256(1), sellSalt));

        vm.prank(alice);
        market.commitSell(sellHash);

        vm.roll(block.number + 1);

        uint256 balanceBefore = alice.balance;

        vm.prank(alice);
        uint256 ethOut = market.revealSell(sellAmount, 1, sellSalt);

        assertGt(ethOut, 0);
        assertEq(alice.balance, balanceBefore + ethOut);
    }

    function testRevealBuyRevertsWhenCommitmentExpired() public {
        vm.deal(alice, 2 ether);

        bytes32 salt = keccak256("buy-expired");
        bytes32 buyHash = keccak256(abi.encode("BUY", alice, uint256(1), salt, 1 ether));

        vm.prank(alice);
        market.commitBuy{value: 1 ether}(buyHash);

        vm.warp(block.timestamp + 1 hours + 1);
        vm.roll(block.number + 1);

        vm.expectRevert("commit-expired");
        vm.prank(alice);
        market.revealBuy(1, salt);
    }

    function testRevealBuyRevertsOnWrongCommitHash() public {
        vm.deal(alice, 2 ether);

        bytes32 correctSalt = keccak256("buy-correct");
        bytes32 wrongSalt = keccak256("buy-wrong");
        bytes32 buyHash = keccak256(abi.encode("BUY", alice, uint256(1), correctSalt, 1 ether));

        vm.prank(alice);
        market.commitBuy{value: 1 ether}(buyHash);

        vm.roll(block.number + 1);

        vm.expectRevert("invalid-commit");
        vm.prank(alice);
        market.revealBuy(1, wrongSalt);
    }

    function testRevealBuyRevertsInSameBlock() public {
        vm.deal(alice, 2 ether);

        bytes32 salt = keccak256("buy-same-block");
        bytes32 buyHash = keccak256(abi.encode("BUY", alice, uint256(1), salt, 1 ether));

        vm.prank(alice);
        market.commitBuy{value: 1 ether}(buyHash);

        vm.expectRevert("reveal-too-soon");
        vm.prank(alice);
        market.revealBuy(1, salt);
    }

    function testDirectTokenTransferDoesNotAffectPricing() public {
        vm.deal(alice, 5 ether);

        uint256 bought = _commitAndRevealBuy(alice, 1 ether, 1, keccak256("buy-for-transfer"));
        assertGt(bought, 0);

        uint256 supplyBefore = market.circulatingSupplyTokens();
        uint256 quoteBefore = market.quoteBuy(0.5 ether);

        uint256 transferAmount = bought / 4;
        assertGt(transferAmount, 0);

        vm.prank(alice);
        token.transfer(address(market), transferAmount * TOKEN_UNIT);

        uint256 supplyAfter = market.circulatingSupplyTokens();
        uint256 quoteAfter = market.quoteBuy(0.5 ether);

        assertEq(supplyAfter, supplyBefore);
        assertEq(quoteAfter, quoteBefore);
    }

    function testSweepExcessTokensTransfersOnlyExcess() public {
        vm.deal(alice, 5 ether);

        uint256 bought = _commitAndRevealBuy(alice, 1 ether, 1, keccak256("buy-for-sweep"));
        assertGt(bought, 0);

        uint256 transferAmount = bought / 3;
        assertGt(transferAmount, 0);

        vm.prank(alice);
        token.transfer(address(market), transferAmount * TOKEN_UNIT);

        uint256 ownerBefore = token.balanceOf(address(this));
        uint256 marketBefore = token.balanceOf(address(market));

        market.sweepExcessTokens();

        assertEq(token.balanceOf(address(this)), ownerBefore + marketBefore);
        assertEq(token.balanceOf(address(market)), 0);
    }

    function _commitAndRevealBuy(address trader, uint256 ethValue, uint256 minTokensOut, bytes32 salt)
        internal
        returns (uint256 tokensOut)
    {
        bytes32 buyHash = keccak256(abi.encode("BUY", trader, minTokensOut, salt, ethValue));

        vm.prank(trader);
        market.commitBuy{value: ethValue}(buyHash);

        vm.roll(block.number + 1);

        vm.prank(trader);
        tokensOut = market.revealBuy(minTokensOut, salt);
    }
}
