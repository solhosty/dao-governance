// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {DAOGovernanceToken} from "./DAOGovernanceToken.sol";

contract DAOTokenMarket is Ownable, ReentrancyGuard {
    uint256 public constant TOKEN_UNIT = 1e18;
    uint256 public constant MIN_COMMIT_BLOCKS = 2;
    uint256 public constant COMMIT_EXPIRY = 1 hours;
    uint256 public constant TWAP_WINDOW = 1 hours;
    uint256 public constant MAX_TOKENS_TO_PURCHASE = 1_000_000_000;
    uint256 private constant BPS_DENOMINATOR = 10_000;
    uint256 private constant MAX_TWAP_DEVIATION_BPS = 2_000;

    struct Commitment {
        address sender;
        uint256 blockNumber;
        uint256 timestamp;
        bool revealed;
    }

    DAOGovernanceToken public immutable token;

    uint256 public basePriceWei;
    uint256 public slopeWei;
    uint256 public marketTokenBalance;
    uint256 public twapCumulativeSupply;
    uint256 public twapSupply;
    uint256 public lastTwapUpdate;
    uint256 public immutable twapStartTime;

    mapping(bytes32 => Commitment) public commitments;

    event TokensPurchased(address indexed buyer, uint256 ethSpent, uint256 tokensMinted);
    event TokensSold(address indexed seller, uint256 tokensSold, uint256 ethReceived);
    event CurveParamsUpdated(uint256 basePriceWei, uint256 slopeWei);
    event TradeCommitted(bytes32 indexed commitmentHash, address indexed sender);
    event TradeCancelled(bytes32 indexed commitmentHash, address indexed sender);
    event TradeRevealed(bytes32 indexed commitmentHash, address indexed sender, bool isBuy);
    event MarketBalanceReconciled(uint256 previousBalance, uint256 newBalance);

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

        marketTokenBalance = token_.balanceOf(address(this));
        twapSupply = _circulatingSupplyTokens(token_.totalSupply(), marketTokenBalance);
        lastTwapUpdate = block.timestamp;
        twapStartTime = block.timestamp;
    }

    function setCurveParams(uint256 basePriceWei_, uint256 slopeWei_) external onlyOwner {
        require(basePriceWei_ > 0, "base=0");
        basePriceWei = basePriceWei_;
        slopeWei = slopeWei_;
        emit CurveParamsUpdated(basePriceWei_, slopeWei_);
    }

    function commitTrade(bytes32 commitmentHash) external {
        require(commitmentHash != bytes32(0), "commitment=0");
        require(commitments[commitmentHash].sender == address(0), "commitment-exists");

        commitments[commitmentHash] = Commitment({
            sender: msg.sender,
            blockNumber: block.number,
            timestamp: block.timestamp,
            revealed: false
        });

        emit TradeCommitted(commitmentHash, msg.sender);
    }

    function revealTrade(
        bool isBuy,
        uint256 amount,
        uint256 minOut,
        bytes32 salt
    ) external payable nonReentrant returns (uint256 amountOut) {
        bytes32 commitmentHash = _tradeCommitment(msg.sender, isBuy, amount, minOut, salt);
        _consumeCommitment(commitmentHash, msg.sender);

        if (isBuy) {
            require(msg.value == amount, "value-mismatch");
            amountOut = _buy(msg.sender, amount, minOut);
        } else {
            require(msg.value == 0, "value-not-allowed");
            amountOut = _sell(msg.sender, amount, minOut);
        }

        emit TradeRevealed(commitmentHash, msg.sender, isBuy);
    }

    function cancelCommit(bytes32 commitmentHash) external {
        Commitment memory commitment = commitments[commitmentHash];
        require(commitment.sender == msg.sender, "not-committer");
        require(!commitment.revealed, "already-revealed");
        require(block.timestamp > commitment.timestamp + COMMIT_EXPIRY, "commit-not-expired");

        delete commitments[commitmentHash];
        emit TradeCancelled(commitmentHash, msg.sender);
    }

    function deposit(uint256 tokenAmount) external onlyOwner nonReentrant {
        require(tokenAmount > 0, "amount=0");

        uint256 rawAmount = tokenAmount * TOKEN_UNIT;

        _accrueTwap();
        bool transferred = token.transferFrom(msg.sender, address(this), rawAmount);
        require(transferred, "transfer-failed");

        marketTokenBalance += rawAmount;
        _refreshTwapSupply();
    }

    function reconcileMarketBalance() external onlyOwner returns (uint256 previousBalance, uint256 newBalance) {
        _accrueTwap();

        previousBalance = marketTokenBalance;
        newBalance = token.balanceOf(address(this));
        marketTokenBalance = newBalance;
        _refreshTwapSupply();

        emit MarketBalanceReconciled(previousBalance, newBalance);
    }

    function buy(uint256 minTokensOut) external payable nonReentrant returns (uint256 tokensOut) {
        bytes32 commitmentHash = _tradeCommitment(msg.sender, true, msg.value, minTokensOut, bytes32(0));
        _consumeCommitment(commitmentHash, msg.sender);

        tokensOut = _buy(msg.sender, msg.value, minTokensOut);
        emit TradeRevealed(commitmentHash, msg.sender, true);
    }

    function sell(uint256 tokenAmount, uint256 minEthOut) external nonReentrant returns (uint256 ethOut) {
        bytes32 commitmentHash = _tradeCommitment(msg.sender, false, tokenAmount, minEthOut, bytes32(0));
        _consumeCommitment(commitmentHash, msg.sender);

        ethOut = _sell(msg.sender, tokenAmount, minEthOut);
        emit TradeRevealed(commitmentHash, msg.sender, false);
    }

    function _buy(address buyer, uint256 payment, uint256 minTokensOut) internal returns (uint256 tokensOut) {
        require(payment > 0, "value=0");

        _accrueTwap();
        tokensOut = quoteBuy(payment);
        require(tokensOut > 0, "insufficient-value");
        require(tokensOut >= minTokensOut, "slippage");

        uint256 supplyTokens = circulatingSupplyTokens();
        uint256 spent = costForTokens(supplyTokens, tokensOut);
        uint256 refund = payment - spent;

        token.mint(buyer, tokensOut);
        _refreshTwapSupply();

        if (refund > 0) {
            (bool ok, ) = buyer.call{value: refund}("");
            require(ok, "refund-failed");
        }

        emit TokensPurchased(buyer, spent, tokensOut);
    }

    function _sell(address seller, uint256 tokenAmount, uint256 minEthOut) internal returns (uint256 ethOut) {
        require(tokenAmount > 0, "amount=0");

        _accrueTwap();
        ethOut = quoteSell(tokenAmount);
        require(ethOut >= minEthOut, "slippage");
        require(ethOut > 0, "insufficient-liquidity");
        require(address(this).balance >= ethOut, "insufficient-liquidity");

        uint256 rawAmount = tokenAmount * TOKEN_UNIT;
        bool transferred = token.transferFrom(seller, address(this), rawAmount);
        require(transferred, "transfer-failed");

        marketTokenBalance += rawAmount;
        _refreshTwapSupply();

        (bool ok, ) = seller.call{value: ethOut}("");
        require(ok, "payout-failed");

        emit TokensSold(seller, tokenAmount, ethOut);
    }

    function quoteBuy(uint256 ethAmount) public view returns (uint256) {
        uint256 supplyTokens = circulatingSupplyTokens();
        uint256 low = 0;
        uint256 high = 1;

        while (costForTokens(supplyTokens, high) <= ethAmount) {
            if (high >= MAX_TOKENS_TO_PURCHASE) {
                high = MAX_TOKENS_TO_PURCHASE;
                break;
            }

            high *= 2;
            if (high > MAX_TOKENS_TO_PURCHASE) {
                high = MAX_TOKENS_TO_PURCHASE;
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
        return _circulatingSupplyTokens(token.totalSupply(), marketTokenBalance);
    }

    function costForTokens(uint256 currentSupplyTokens, uint256 tokensToBuy) public view returns (uint256) {
        if (tokensToBuy == 0) return 0;

        uint256 boundedTokensToBuy = tokensToBuy;
        if (boundedTokensToBuy > MAX_TOKENS_TO_PURCHASE) {
            boundedTokensToBuy = MAX_TOKENS_TO_PURCHASE;
        }

        uint256 boundedSupplyTokens = _boundedSupply(currentSupplyTokens);

        uint256 linearCost = boundedTokensToBuy * basePriceWei;
        uint256 supplyComponent = boundedTokensToBuy * boundedSupplyTokens;
        uint256 progressiveComponent = (boundedTokensToBuy * (boundedTokensToBuy - 1)) / 2;
        uint256 curveCost = slopeWei * (supplyComponent + progressiveComponent);

        return linearCost + curveCost;
    }

    function proceedsForTokens(uint256 currentSupplyTokens, uint256 tokensToSell) public view returns (uint256) {
        if (tokensToSell == 0 || tokensToSell > currentSupplyTokens) return 0;
        uint256 startingSupply = currentSupplyTokens - tokensToSell;
        return costForTokens(startingSupply, tokensToSell);
    }

    function currentTwapSupplyTokens() public view returns (uint256) {
        if (block.timestamp <= twapStartTime) {
            return twapSupply;
        }

        uint256 cumulative = twapCumulativeSupply;
        if (block.timestamp > lastTwapUpdate) {
            cumulative += twapSupply * (block.timestamp - lastTwapUpdate);
        }

        uint256 elapsed = block.timestamp - twapStartTime;
        if (elapsed == 0) {
            return twapSupply;
        }

        return cumulative / elapsed;
    }

    function tradeCommitment(
        address sender,
        bool isBuy,
        uint256 amount,
        uint256 minOut,
        bytes32 salt
    ) external pure returns (bytes32) {
        return _tradeCommitment(sender, isBuy, amount, minOut, salt);
    }

    function _consumeCommitment(bytes32 commitmentHash, address sender) internal {
        Commitment storage commitment = commitments[commitmentHash];
        require(commitment.sender == sender, "bad-commitment");
        require(!commitment.revealed, "already-revealed");
        require(block.number >= commitment.blockNumber + MIN_COMMIT_BLOCKS, "commit-too-fresh");
        require(block.timestamp <= commitment.timestamp + COMMIT_EXPIRY, "commit-expired");

        commitment.revealed = true;
    }

    function _accrueTwap() internal {
        if (block.timestamp > lastTwapUpdate) {
            twapCumulativeSupply += twapSupply * (block.timestamp - lastTwapUpdate);
            lastTwapUpdate = block.timestamp;
        }
    }

    function _refreshTwapSupply() internal {
        twapSupply = circulatingSupplyTokens();
    }

    function _boundedSupply(uint256 currentSupplyTokens) internal view returns (uint256) {
        uint256 twapSupplyTokens = currentTwapSupplyTokens();
        if (twapSupplyTokens == 0) {
            return currentSupplyTokens;
        }

        uint256 maxDeviation = (twapSupplyTokens * MAX_TWAP_DEVIATION_BPS) / BPS_DENOMINATOR;
        uint256 lowerBound = twapSupplyTokens > maxDeviation ? twapSupplyTokens - maxDeviation : 0;
        uint256 upperBound = twapSupplyTokens + maxDeviation;

        if (currentSupplyTokens < lowerBound) {
            return lowerBound;
        }

        if (currentSupplyTokens > upperBound) {
            return upperBound;
        }

        return currentSupplyTokens;
    }

    function _circulatingSupplyTokens(uint256 totalSupply, uint256 marketBalance) internal pure returns (uint256) {
        if (marketBalance >= totalSupply) {
            return 0;
        }

        return (totalSupply - marketBalance) / TOKEN_UNIT;
    }

    function _tradeCommitment(
        address sender,
        bool isBuy,
        uint256 amount,
        uint256 minOut,
        bytes32 salt
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(sender, isBuy, amount, minOut, salt));
    }

    receive() external payable {
        revert("use-commit-reveal");
    }
}
