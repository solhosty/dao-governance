// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DAOFactory} from "../src/DAOFactory.sol";
import {DAOGovernanceToken} from "../src/DAOGovernanceToken.sol";
import {DAOTokenMarket} from "../src/DAOTokenMarket.sol";

contract DAOFactoryTest is Test {
    DAOFactory internal factory;

    function setUp() public {
        factory = new DAOFactory(address(this));
    }

    function testCreateDAO() public {
        uint256 id = factory.createDAO("Alpha DAO", "ALPHA", 1_000, 0.0001 ether, 0.00001 ether, 4);

        DAOFactory.DAOInfo memory info = factory.getDAO(id);
        assertEq(info.id, 0);
        assertEq(info.creator, address(this));
        assertTrue(info.token != address(0));
        assertTrue(info.dao != address(0));
        assertTrue(info.market != address(0));
        assertTrue(info.timelock != address(0));

        DAOGovernanceToken token = DAOGovernanceToken(info.token);
        DAOTokenMarket market = DAOTokenMarket(payable(info.market));

        assertEq(token.owner(), address(market));
        assertEq(token.balanceOf(address(this)), 1_000 * token.TOKEN_UNIT());
        assertEq(market.basePriceWei(), 0.0001 ether);
    }
}
