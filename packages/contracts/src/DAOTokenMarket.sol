// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {DAOGovernanceToken} from "./DAOGovernanceToken.sol";

contract DAOTokenMarket is Ownable, ReentrancyGuard {
    uint256 private constant TOKEN_UNIT = 1e18;
    uint256 private constant COMMITMENT_TTL = 1 hours;

    struct Commitment {
        bytes32 commitHash;
        uint256 ethValue;
        uint256 timestamp;
        uint256 blockNumber;
    }

    DAOGovernanceToken public immutable token;

    uint256 public basePriceWei;
    uint256 public slopeWei;
    uint256 private _internalTokenBalance;

    mapping(address trader => Commitment commitment) private commitments;

    event TokensPurchased(address indexed buyer, uint256 ethSpent, uint256 tokensMinted);
    event TokensSold(address indexed seller, uint256 tokensSold, uint256 ethReceived);
    event CurveParamsUpdated(uint256 basePriceWei, uint256 slopeWei);
    event TradeCommitted(address indexed trader, bytes32 commitHash);
    event TradeRevealed(address indexed trader);

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

    function commitBuy(bytes32 commitHash) external payable {
        _commit(commitHash, msg.value);
    }

    function revealBuy(uint256 minTokensOut, bytes32 salt)
        external
        nonReentrant
        returns (uint256 tokensOut)
    {
        Commitment memory commitment = _consumeCommitment(
            keccak256(abi.encode("BUY", msg.sender, minTokensOut, salt, commitments[msg.sender].ethValue))
        );

        tokensOut = _buy(msg.sender, commitment.ethValue, minTokensOut);
        emit TradeRevealed(msg.sender);
    }

    function commitSell(bytes32 commitHash) external {
        _commit(commitHash, 0);
    }

    function revealSell(uint256 tokenAmount, uint256 minEthOut, bytes32 salt)
        external
        nonReentrant
        returns (uint256 ethOut)
    {
        _consumeCommitment(keccak256(abi.encode("SELL", msg.sender, tokenAmount, minEthOut, salt)));

        ethOut = _sell(msg.sender, tokenAmount, minEthOut);
        emit TradeRevealed(msg.sender);
    }

    function cancelCommitment() external nonReentrant {
        Commitment memory commitment = commitments[msg.sender];
        require(commitment.commitHash != bytes32(0), "no-commitment");

        delete commitments[msg.sender];

        if (commitment.ethValue > 0) {
            (bool ok, ) = msg.sender.call{value: commitment.ethValue}("");
            require(ok, "refund-failed");
        }
    }

    function sweepExcessTokens() external onlyOwner {
        uint256 marketBalance = token.balanceOf(address(this));
        require(marketBalance > _internalTokenBalance, "no-excess");

        uint256 excess = marketBalance - _internalTokenBalance;
        bool transferred = token.transfer(owner(), excess);
        require(transferred, "sweep-failed");
    }

    function _commit(bytes32 commitHash, uint256 ethValue) private {
        require(commitHash != bytes32(0), "hash=0");
        require(commitments[msg.sender].commitHash == bytes32(0), "active-commitment");

        commitments[msg.sender] = Commitment({
            commitHash: commitHash,
            ethValue: ethValue,
            timestamp: block.timestamp,
            blockNumber: block.number
        });

        emit TradeCommitted(msg.sender, commitHash);
    }

    function _consumeCommitment(bytes32 expectedHash) private returns (Commitment memory commitment) {
        commitment = commitments[msg.sender];
        require(commitment.commitHash != bytes32(0), "no-commitment");
        require(block.number > commitment.blockNumber, "reveal-too-soon");
        require(block.timestamp <= commitment.timestamp + COMMITMENT_TTL, "commit-expired");
        require(commitment.commitHash == expectedHash, "invalid-commit");

        delete commitments[msg.sender];
    }

    function _sell(address seller, uint256 tokenAmount, uint256 minEthOut) internal returns (uint256 ethOut) {
        require(tokenAmount > 0, "amount=0");

        ethOut = quoteSell(tokenAmount);
        require(ethOut >= minEthOut, "slippage");
        require(ethOut > 0, "insufficient-liquidity");
        require(address(this).balance >= ethOut, "insufficient-liquidity");

        uint256 tokenAmountWei = tokenAmount * TOKEN_UNIT;
        bool transferred = token.transferFrom(seller, address(this), tokenAmountWei);
        require(transferred, "transfer-failed");
        _internalTokenBalance += tokenAmountWei;

        (bool ok, ) = seller.call{value: ethOut}("");
        require(ok, "payout-failed");

        emit TokensSold(seller, tokenAmount, ethOut);
    }

    function _buy(address buyer, uint256 payment, uint256 minTokensOut) internal returns (uint256 tokensOut) {
        require(payment > 0, "value=0");

        tokensOut = quoteBuy(payment);
        require(tokensOut > 0, "insufficient-value");
        require(tokensOut >= minTokensOut, "slippage");

        uint256 supplyTokens = circulatingSupplyTokens();
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
        uint256 supplyTokens = circulatingSupplyTokens();
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

    function quoteSell(uint256 tokenAmount) public view returns (uint256) {
        if (tokenAmount == 0) return 0;

        uint256 supplyTokens = circulatingSupplyTokens();
        if (tokenAmount > supplyTokens) {
            return 0;
        }

        return proceedsForTokens(supplyTokens, tokenAmount);
    }

    function circulatingSupplyTokens() public view returns (uint256) {
        return (token.totalSupply() - _internalTokenBalance) / TOKEN_UNIT;
    }

    function costForTokens(uint256 currentSupplyTokens, uint256 tokensToBuy) public view returns (uint256) {
        if (tokensToBuy == 0) return 0;

        uint256 linearCost = tokensToBuy * basePriceWei;
        uint256 supplyComponent = tokensToBuy * currentSupplyTokens;
        uint256 progressiveComponent = (tokensToBuy * (tokensToBuy - 1)) / 2;
        uint256 curveCost = slopeWei * (supplyComponent + progressiveComponent);

        return linearCost + curveCost;
    }

    function proceedsForTokens(uint256 currentSupplyTokens, uint256 tokensToSell) public view returns (uint256) {
        if (tokensToSell == 0 || tokensToSell > currentSupplyTokens) return 0;
        uint256 startingSupply = currentSupplyTokens - tokensToSell;
        return costForTokens(startingSupply, tokensToSell);
    }

}
