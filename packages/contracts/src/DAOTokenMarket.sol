// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {DAOGovernanceToken} from "./DAOGovernanceToken.sol";

contract DAOTokenMarket is Ownable, ReentrancyGuard {
    DAOGovernanceToken public immutable token;

    uint256 public basePriceWei;
    uint256 public slopeWei;
    uint256 public constant REVEAL_DELAY = 2 minutes;
    uint256 public constant REVEAL_WINDOW = 30 minutes;

    bytes32 private constant ACTION_BUY = keccak256("BUY");
    bytes32 private constant ACTION_SELL = keccak256("SELL");

    struct Commitment {
        address user;
        bytes32 actionHash;
        uint256 commitTime;
        bool revealed;
    }

    mapping(bytes32 => Commitment) public commitments;
    mapping(address => uint256) public nonces;

    event TokensPurchased(address indexed buyer, uint256 ethSpent, uint256 tokensMinted);
    event TokensSold(address indexed seller, uint256 tokensSold, uint256 ethReceived);
    event CurveParamsUpdated(uint256 basePriceWei, uint256 slopeWei);
    event TradeCommitted(address indexed user, bytes32 indexed commitHash, bytes32 actionHash, uint256 nonce);
    event TradeRevealed(address indexed user, bytes32 indexed commitHash, bytes32 actionHash);

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

    function buy(uint256 minTokensOut) external payable {
        minTokensOut;
        revert("use-commit-reveal");
    }

    function sell(uint256 tokenAmount, uint256 minEthOut) external pure {
        tokenAmount;
        minEthOut;
        revert("use-commit-reveal");
    }

    function commit(bytes32 actionHash) external returns (bytes32 commitHash) {
        require(actionHash != bytes32(0), "action-hash=0");

        uint256 nonce = nonces[msg.sender];
        commitHash = keccak256(abi.encode(msg.sender, actionHash, nonce));

        Commitment storage existing = commitments[commitHash];
        require(existing.user == address(0), "commit-exists");

        commitments[commitHash] = Commitment({
            user: msg.sender,
            actionHash: actionHash,
            commitTime: block.timestamp,
            revealed: false
        });

        nonces[msg.sender] = nonce + 1;
        emit TradeCommitted(msg.sender, commitHash, actionHash, nonce);
    }

    function revealBuy(
        uint256 minTokensOut,
        uint256 nonce,
        uint256 deadline,
        bytes32 commitHash
    ) external payable nonReentrant returns (uint256 tokensOut) {
        require(block.timestamp <= deadline, "expired");

        bytes32 actionHash = getBuyActionHash(msg.value, minTokensOut, nonce, deadline);
        _consumeCommitment(commitHash, actionHash, nonce);

        tokensOut = _buy(msg.sender, msg.value, minTokensOut);
        emit TradeRevealed(msg.sender, commitHash, actionHash);
    }

    function revealSell(
        uint256 tokenAmount,
        uint256 minEthOut,
        uint256 nonce,
        uint256 deadline,
        bytes32 commitHash
    ) external nonReentrant returns (uint256 ethOut) {
        require(block.timestamp <= deadline, "expired");
        require(tokenAmount > 0, "amount=0");

        bytes32 actionHash = getSellActionHash(tokenAmount, minEthOut, nonce, deadline);
        _consumeCommitment(commitHash, actionHash, nonce);

        ethOut = quoteSell(tokenAmount);
        require(ethOut >= minEthOut, "slippage");
        require(ethOut > 0, "insufficient-liquidity");
        require(address(this).balance >= ethOut, "insufficient-liquidity");

        bool transferred = token.transferFrom(msg.sender, address(this), tokenAmount * 1e18);
        require(transferred, "transfer-failed");

        (bool ok, ) = msg.sender.call{value: ethOut}("");
        require(ok, "payout-failed");

        emit TokensSold(msg.sender, tokenAmount, ethOut);
        emit TradeRevealed(msg.sender, commitHash, actionHash);
    }

    function getBuyActionHash(
        uint256 payment,
        uint256 minTokensOut,
        uint256 nonce,
        uint256 deadline
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(ACTION_BUY, payment, minTokensOut, nonce, deadline));
    }

    function getSellActionHash(
        uint256 tokenAmount,
        uint256 minEthOut,
        uint256 nonce,
        uint256 deadline
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(ACTION_SELL, tokenAmount, minEthOut, nonce, deadline));
    }

    function _consumeCommitment(bytes32 commitHash, bytes32 actionHash, uint256 nonce) internal {
        bytes32 expectedCommitHash = keccak256(abi.encode(msg.sender, actionHash, nonce));
        require(expectedCommitHash == commitHash, "commit-hash");

        Commitment storage commitment = commitments[commitHash];
        require(commitment.user == msg.sender, "commit-user");
        require(commitment.actionHash == actionHash, "action-hash");
        require(!commitment.revealed, "already-revealed");

        uint256 earliestReveal = commitment.commitTime + REVEAL_DELAY;
        require(block.timestamp >= earliestReveal, "reveal-too-early");
        require(block.timestamp <= earliestReveal + REVEAL_WINDOW, "commit-expired");

        commitment.revealed = true;
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
        uint256 marketBalance = token.balanceOf(address(this));
        return (token.totalSupply() - marketBalance) / 1e18;
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

    receive() external payable {
        revert("use-commit-reveal");
    }
}
