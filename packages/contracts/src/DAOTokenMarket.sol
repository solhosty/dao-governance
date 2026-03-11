// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {DAOGovernanceToken} from "./DAOGovernanceToken.sol";

contract DAOTokenMarket is Ownable, ReentrancyGuard {
    DAOGovernanceToken public immutable token;

    uint256 public basePriceWei;
    uint256 public slopeWei;

    event TokensPurchased(address indexed buyer, uint256 ethSpent, uint256 tokensMinted);
    event CurveParamsUpdated(uint256 basePriceWei, uint256 slopeWei);

    constructor(
        DAOGovernanceToken token_,
        address initialOwner_,
        uint256 basePriceWei_,
        uint256 slopeWei_
    ) Ownable(initialOwner_) {
        require(address(token_) != address(0), "token=0");
        require(basePriceWei_ > 0, "base=0");

        token = token_;
        basePriceWei = basePriceWei_;
        slopeWei = slopeWei_;
    }

    function setCurveParams(uint256 basePriceWei_, uint256 slopeWei_) external onlyOwner {
        require(basePriceWei_ > 0, "base=0");
        basePriceWei = basePriceWei_;
        slopeWei = slopeWei_;
        emit CurveParamsUpdated(basePriceWei_, slopeWei_);
    }

    function buy(uint256 minTokensOut) external payable nonReentrant returns (uint256 tokensOut) {
        return _buy(msg.sender, msg.value, minTokensOut);
    }

    function _buy(address buyer, uint256 payment, uint256 minTokensOut) internal returns (uint256 tokensOut) {
        require(payment > 0, "value=0");

        tokensOut = quoteBuy(payment);
        require(tokensOut > 0, "insufficient-value");
        require(tokensOut >= minTokensOut, "slippage");

        uint256 supplyTokens = token.totalSupply() / 1e18;
        uint256 spent = costForTokens(supplyTokens, tokensOut);
        uint256 refund = payment - spent;

        token.mint(buyer, tokensOut);

        if (refund > 0) {
            (bool ok, ) = buyer.call{value: refund}("");
            require(ok, "refund-failed");
        }

        emit TokensPurchased(buyer, spent, tokensOut);
    }

    function quoteBuy(uint256 ethAmount) public view returns (uint256) {
        uint256 supplyTokens = token.totalSupply() / 1e18;
        uint256 low = 0;
        uint256 high = 1;

        while (costForTokens(supplyTokens, high) <= ethAmount) {
            high *= 2;
            if (high > 1_000_000_000) {
                break;
            }
        }

        while (low < high) {
            uint256 mid = (low + high + 1) / 2;
            if (costForTokens(supplyTokens, mid) <= ethAmount) {
                low = mid;
            } else {
                high = mid - 1;
            }
        }

        return low;
    }

    function costForTokens(uint256 currentSupplyTokens, uint256 tokensToBuy) public view returns (uint256) {
        if (tokensToBuy == 0) return 0;

        uint256 linearCost = tokensToBuy * basePriceWei;
        uint256 supplyComponent = tokensToBuy * currentSupplyTokens;
        uint256 progressiveComponent = (tokensToBuy * (tokensToBuy - 1)) / 2;
        uint256 curveCost = slopeWei * (supplyComponent + progressiveComponent);

        return linearCost + curveCost;
    }

    receive() external payable {
        _buy(msg.sender, msg.value, 0);
    }
}
