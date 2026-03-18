// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DAOGovernanceToken} from "../src/DAOGovernanceToken.sol";
import {DAOTokenMarket} from "../src/DAOTokenMarket.sol";

contract DAOTokenMarketSecurityTest is Test {
    DAOGovernanceToken internal token;
    DAOTokenMarket internal market;

    address internal alice = address(0xA11CE);

    function setUp() public {
        token = new DAOGovernanceToken("Test Governance Token", "TGT", address(this), 0);
        market = new DAOTokenMarket(token, address(this), 0.0001 ether, 0.00001 ether);
        token.transferOwnership(address(market));

        vm.deal(alice, 10 ether);
    }

    function testCommitBuySucceedsWithCorrectSalt() public {
        bytes32 salt = keccak256("buy-ok");
        uint256 minTokensOut = 1;
        bytes32 hash = keccak256(abi.encodePacked("buy", uint256(1 ether), minTokensOut, salt));

        vm.startPrank(alice);
        market.commit(hash);
        vm.stopPrank();

        vm.roll(block.number + 1);

        vm.prank(alice);
        uint256 bought = market.buy{value: 1 ether}(minTokensOut, salt);
        assertGt(bought, 0);
    }

    function testBuyRevertsWithoutCommit() public {
        vm.prank(alice);
        vm.expectRevert(bytes("commit-missing"));
        market.buy{value: 1 ether}(1, bytes32(0));
    }

    function testBuyRevertsWithWrongSalt() public {
        bytes32 commitSalt = keccak256("buy-commit");
        bytes32 wrongSalt = keccak256("buy-wrong");
        uint256 minTokensOut = 1;
        bytes32 hash = keccak256(abi.encodePacked("buy", uint256(1 ether), minTokensOut, commitSalt));

        vm.prank(alice);
        market.commit(hash);

        vm.roll(block.number + 1);

        vm.prank(alice);
        vm.expectRevert(bytes("commit-mismatch"));
        market.buy{value: 1 ether}(minTokensOut, wrongSalt);
    }

    function testBuyRevertsBeforeDelay() public {
        bytes32 salt = keccak256("buy-delay");
        uint256 minTokensOut = 1;
        bytes32 hash = keccak256(abi.encodePacked("buy", uint256(1 ether), minTokensOut, salt));

        vm.prank(alice);
        market.commit(hash);

        vm.prank(alice);
        vm.expectRevert(bytes("commit-too-soon"));
        market.buy{value: 1 ether}(minTokensOut, salt);
    }

    function testBuyRevertsAfterCommitExpires() public {
        bytes32 salt = keccak256("buy-expired");
        uint256 minTokensOut = 1;
        bytes32 hash = keccak256(abi.encodePacked("buy", uint256(1 ether), minTokensOut, salt));

        vm.prank(alice);
        market.commit(hash);

        vm.roll(block.number + market.COMMIT_MAX_AGE() + 1);

        vm.prank(alice);
        vm.expectRevert(bytes("commit-expired"));
        market.buy{value: 1 ether}(minTokensOut, salt);
    }

    function testSellUsesCommitRevealFlow() public {
        uint256 bought = _buyWithCommit(alice, 1 ether, 1, keccak256("buy-for-sell"));
        uint256 sellAmount = bought / 2;
        uint256 tokenUnit = token.TOKEN_UNIT();

        vm.prank(alice);
        token.approve(address(market), sellAmount * tokenUnit);

        bytes32 sellSalt = keccak256("sell-ok");
        bytes32 sellHash = keccak256(abi.encodePacked("sell", sellAmount, uint256(0), sellSalt));

        vm.prank(alice);
        market.commit(sellHash);

        vm.roll(block.number + market.COMMIT_MIN_DELAY() + 1);

        vm.prank(alice);
        uint256 ethOut = market.sell(sellAmount, 0, sellSalt);
        assertGt(ethOut, 0);
    }

    function testDirectTransferDoesNotAffectCirculatingSupply() public {
        _buyWithCommit(alice, 1 ether, 1, keccak256("buy-for-direct-transfer"));

        uint256 beforeSupply = market.circulatingSupplyTokens();
        uint256 transferAmount = 10 * token.TOKEN_UNIT();

        vm.prank(alice);
        bool transferred = token.transfer(address(market), transferAmount);
        assertTrue(transferred);

        uint256 afterSupply = market.circulatingSupplyTokens();
        assertEq(afterSupply, beforeSupply);
    }

    function testSkimRecoversExcessAndOnlyOwnerCanCall() public {
        _buyWithCommit(alice, 1 ether, 1, keccak256("buy-for-skim"));

        uint256 transferAmount = 10 * token.TOKEN_UNIT();
        vm.prank(alice);
        bool transferred = token.transfer(address(market), transferAmount);
        assertTrue(transferred);

        uint256 ownerBalanceBefore = token.balanceOf(address(this));
        market.skim(address(this));

        uint256 ownerBalanceAfter = token.balanceOf(address(this));
        assertEq(ownerBalanceAfter, ownerBalanceBefore + transferAmount);

        vm.prank(alice);
        vm.expectRevert();
        market.skim(alice);
    }

    function _buyWithCommit(address buyer, uint256 value, uint256 minTokensOut, bytes32 salt)
        internal
        returns (uint256 bought)
    {
        bytes32 hash = keccak256(abi.encodePacked("buy", value, minTokensOut, salt));

        vm.prank(buyer);
        market.commit(hash);

        vm.roll(block.number + 1);

        vm.prank(buyer);
        bought = market.buy{value: value}(minTokensOut, salt);
    }
}
