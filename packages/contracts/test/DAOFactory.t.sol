// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DAOFactory} from "../src/DAOFactory.sol";
import {DAOGovernanceToken} from "../src/DAOGovernanceToken.sol";
import {DAOTokenMarket} from "../src/DAOTokenMarket.sol";
import {TokenDeployer} from "../src/deployers/TokenDeployer.sol";
import {GovernorDeployer} from "../src/deployers/GovernorDeployer.sol";
import {MarketDeployer} from "../src/deployers/MarketDeployer.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

contract DAOFactoryTest is Test {
    DAOFactory internal factory;

    function setUp() public {
        factory = new DAOFactory(address(this));
    }

    function testCreateDAO() public {
        DAOFactory.PredictedAddresses memory predicted = factory.predictAddresses(
            address(this),
            "Alpha DAO",
            "Alpha Governance Token",
            "ALPHA",
            1_000,
            0.0001 ether,
            0.00001 ether,
            4
        );

        uint256 id = factory.createDAO(
            "Alpha DAO",
            "Alpha Governance Token",
            "ALPHA",
            1_000,
            0.0001 ether,
            0.00001 ether,
            4
        );

        DAOFactory.DAOInfo memory info = factory.getDAO(id);
        assertEq(info.id, 0);
        assertEq(info.name, "Alpha DAO");
        assertEq(info.tokenName, "Alpha Governance Token");
        assertEq(info.symbol, "ALPHA");
        assertEq(info.creator, address(this));
        assertTrue(info.token != address(0));
        assertTrue(info.dao != address(0));
        assertTrue(info.market != address(0));
        assertTrue(info.timelock != address(0));
        assertEq(info.token, predicted.token);
        assertEq(info.dao, predicted.dao);
        assertEq(info.market, predicted.market);
        assertEq(info.timelock, predicted.timelock);

        DAOGovernanceToken token = DAOGovernanceToken(info.token);
        DAOTokenMarket market = DAOTokenMarket(payable(info.market));

        assertEq(token.owner(), address(market));
        assertEq(token.name(), "Alpha Governance Token");
        assertEq(token.symbol(), "ALPHA");
        assertEq(token.balanceOf(address(this)), 1_000 * token.TOKEN_UNIT());
        assertEq(market.basePriceWei(), 0.0001 ether);
    }

    function testDeployerFunctionsRevertForNonFactoryCaller() public {
        bytes32 salt = keccak256("salt");

        TokenDeployer tokenDeployer = factory.tokenDeployer();
        vm.prank(address(0xBEEF));
        vm.expectRevert("only-factory");
        tokenDeployer.deploy(salt, "Token", "TKN", address(this), 1_000);

        MarketDeployer marketDeployer = factory.marketDeployer();
        vm.prank(address(0xBEEF));
        vm.expectRevert("only-factory");
        marketDeployer.deploy(salt, DAOGovernanceToken(address(0)), address(this), 1, 1);

        GovernorDeployer governorDeployer = factory.governorDeployer();
        vm.prank(address(0xBEEF));
        vm.expectRevert("only-factory");
        governorDeployer.deploy(salt, salt, "Gov", IVotes(address(0)), 1, 1, 1, address(this));
    }
}
