// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DAOGovernanceToken} from "../src/DAOGovernanceToken.sol";
import {DAOTokenMarket} from "../src/DAOTokenMarket.sol";

contract SecurityFixesTest is Test {
    DAOGovernanceToken internal token;
    DAOTokenMarket internal market;

    uint256 internal constant BASE_PRICE = 0.0001 ether;
    uint256 internal constant SLOPE = 0.00001 ether;

    address internal alice = address(0xA11CE);

    function setUp() public {
        token = new DAOGovernanceToken("Governance", "GOV", address(this), 0);
        market = new DAOTokenMarket(token, address(this), BASE_PRICE, SLOPE);
        token.transferOwnership(address(market));
    }

    function testSetCurveParamsRevertsWhenBaseIncreaseExceedsCap() public {
        vm.expectRevert("base-change-too-large");
        market.setCurveParams(BASE_PRICE * 2 + 1, SLOPE);
    }

    function testSetCurveParamsRevertsWhenSlopeIncreaseExceedsCap() public {
        vm.expectRevert("slope-change-too-large");
        market.setCurveParams(BASE_PRICE, SLOPE * 2 + 1);
    }

    function testSetCurveParamsRevertsWhenUpdateMakesMarketInsolvent() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        market.buy{value: 1 ether}(1);

        vm.expectRevert("insufficient-reserves");
        market.setCurveParams(BASE_PRICE * 2, SLOPE * 2);
    }

    function testSetCurveParamsAllowsSolventDecrease() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        market.buy{value: 1 ether}(1);

        uint256 nextBase = BASE_PRICE / 2;
        uint256 nextSlope = SLOPE / 2;

        market.setCurveParams(nextBase, nextSlope);

        assertEq(market.basePriceWei(), nextBase);
        assertEq(market.slopeWei(), nextSlope);
    }
}
