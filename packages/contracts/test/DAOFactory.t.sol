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

contract DAOFactoryTest is Test {
    DAOFactory internal factory;

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
    }

    function testCreateDAO() public {
        DAOFactory.PredictedAddresses memory predicted = factory.predictAddresses(
            address(this),
            "Alpha DAO",
            "ALPHA",
            1_000,
            0.0001 ether,
            0.00001 ether,
            4
        );

        uint256 id = factory.createDAO("Alpha DAO", "ALPHA", 1_000, 0.0001 ether, 0.00001 ether, 4);

        DAOFactory.DAOInfo memory info = factory.getDAO(id);
        assertEq(info.id, 0);
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
        assertEq(token.balanceOf(address(this)), 1_000 * token.TOKEN_UNIT());
        assertEq(market.basePriceWei(), 0.0001 ether);
    }
}
