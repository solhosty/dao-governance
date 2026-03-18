// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {DAOGovernanceToken} from "./DAOGovernanceToken.sol";

contract DAOTokenMarket is Ownable, ReentrancyGuard {
    DAOGovernanceToken public immutable token;

    uint256 public basePriceWei;
    uint256 public slopeWei;
    uint256 private _internalTokenBalance;

    uint256 public constant REVEAL_DELAY = 1;
    uint256 public constant COMMIT_EXPIRY = 300;

    struct BuyCommit {
        bytes32 commitHash;
        uint256 ethAmount;
        uint256 blockNumber;
    }

    struct SellCommit {
        bytes32 commitHash;
        uint256 tokenAmount;
        uint256 blockNumber;
    }

    mapping(address => BuyCommit) public buyCommits;
    mapping(address => SellCommit) public sellCommits;
    bool public instantTradingEnabled;

    event TokensPurchased(address indexed buyer, uint256 ethSpent, uint256 tokensMinted);
    event TokensSold(address indexed seller, uint256 tokensSold, uint256 ethReceived);
    event CurveParamsUpdated(uint256 basePriceWei, uint256 slopeWei);
    event BuyCommitted(address indexed buyer, bytes32 indexed commitHash, uint256 ethAmount, uint256 blockNumber);
    event SellCommitted(
        address indexed seller,
        bytes32 indexed commitHash,
        uint256 tokenAmount,
        uint256 blockNumber
    );
    event CommitReclaimed(address indexed account, uint256 ethAmount, uint256 tokenAmount);
    event InstantTradingEnabledUpdated(bool enabled);

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
        _internalTokenBalance = 0;
    }

    function setCurveParams(uint256 basePriceWei_, uint256 slopeWei_) external onlyOwner {
        require(basePriceWei_ > 0, "base=0");
        basePriceWei = basePriceWei_;
        slopeWei = slopeWei_;
        emit CurveParamsUpdated(basePriceWei_, slopeWei_);
    }

    function setInstantTradingEnabled(bool enabled) external onlyOwner {
        instantTradingEnabled = enabled;
        emit InstantTradingEnabledUpdated(enabled);
    }

    function commitBuy(bytes32 commitHash) external payable nonReentrant {
        require(commitHash != bytes32(0), "hash=0");
        require(msg.value > 0, "value=0");

        BuyCommit storage existing = buyCommits[msg.sender];
        require(existing.commitHash == bytes32(0), "active-buy-commit");

        buyCommits[msg.sender] = BuyCommit({commitHash: commitHash, ethAmount: msg.value, blockNumber: block.number});

        emit BuyCommitted(msg.sender, commitHash, msg.value, block.number);
    }

    function revealBuy(uint256 minTokensOut, bytes32 secret)
        external
        nonReentrant
        returns (uint256 tokensOut)
    {
        BuyCommit memory userCommit = buyCommits[msg.sender];
        require(userCommit.commitHash != bytes32(0), "no-buy-commit");
        require(block.number >= userCommit.blockNumber + REVEAL_DELAY, "reveal-too-soon");
        require(block.number <= userCommit.blockNumber + COMMIT_EXPIRY, "commit-expired");

        bytes32 expectedHash = keccak256(abi.encodePacked(msg.sender, minTokensOut, secret));
        require(expectedHash == userCommit.commitHash, "invalid-buy-reveal");

        delete buyCommits[msg.sender];
        return _buy(msg.sender, userCommit.ethAmount, minTokensOut);
    }

    function commitSell(bytes32 commitHash, uint256 tokenAmount) external nonReentrant {
        require(commitHash != bytes32(0), "hash=0");
        require(tokenAmount > 0, "amount=0");

        SellCommit storage existing = sellCommits[msg.sender];
        require(existing.commitHash == bytes32(0), "active-sell-commit");

        bool transferred = token.transferFrom(msg.sender, address(this), tokenAmount * 1e18);
        require(transferred, "transfer-failed");
        _internalTokenBalance += tokenAmount * 1e18;

        sellCommits[msg.sender] = SellCommit({commitHash: commitHash, tokenAmount: tokenAmount, blockNumber: block.number});

        emit SellCommitted(msg.sender, commitHash, tokenAmount, block.number);
    }

    function revealSell(uint256 tokenAmount, uint256 minEthOut, bytes32 secret)
        external
        nonReentrant
        returns (uint256 ethOut)
    {
        SellCommit memory userCommit = sellCommits[msg.sender];
        require(userCommit.commitHash != bytes32(0), "no-sell-commit");
        require(block.number >= userCommit.blockNumber + REVEAL_DELAY, "reveal-too-soon");
        require(block.number <= userCommit.blockNumber + COMMIT_EXPIRY, "commit-expired");
        require(tokenAmount == userCommit.tokenAmount, "amount-mismatch");

        bytes32 expectedHash = keccak256(abi.encodePacked(msg.sender, tokenAmount, minEthOut, secret));
        require(expectedHash == userCommit.commitHash, "invalid-sell-reveal");

        delete sellCommits[msg.sender];
        return _executeSell(msg.sender, tokenAmount, minEthOut);
    }

    function reclaimExpiredCommit() external nonReentrant {
        uint256 ethAmount = 0;
        uint256 tokenAmount = 0;

        BuyCommit memory userBuyCommit = buyCommits[msg.sender];
        if (userBuyCommit.commitHash != bytes32(0) && block.number > userBuyCommit.blockNumber + COMMIT_EXPIRY) {
            delete buyCommits[msg.sender];
            ethAmount = userBuyCommit.ethAmount;

            (bool ok, ) = msg.sender.call{value: ethAmount}("");
            require(ok, "buy-reclaim-failed");
        }

        SellCommit memory userSellCommit = sellCommits[msg.sender];
        if (userSellCommit.commitHash != bytes32(0) && block.number > userSellCommit.blockNumber + COMMIT_EXPIRY) {
            delete sellCommits[msg.sender];
            tokenAmount = userSellCommit.tokenAmount;

            _internalTokenBalance -= tokenAmount * 1e18;
            bool transferred = token.transfer(msg.sender, tokenAmount * 1e18);
            require(transferred, "sell-reclaim-failed");
        }

        require(ethAmount > 0 || tokenAmount > 0, "no-expired-commit");
        emit CommitReclaimed(msg.sender, ethAmount, tokenAmount);
    }

    // Deprecated: commit/reveal trading is the secure default.
    function buy(uint256 minTokensOut) external payable nonReentrant returns (uint256 tokensOut) {
        require(instantTradingEnabled, "instant-disabled");
        return _buy(msg.sender, msg.value, minTokensOut);
    }

    // Deprecated: commit/reveal trading is the secure default.
    function sell(uint256 tokenAmount, uint256 minEthOut) external nonReentrant returns (uint256 ethOut) {
        require(instantTradingEnabled, "instant-disabled");
        require(tokenAmount > 0, "amount=0");

        bool transferred = token.transferFrom(msg.sender, address(this), tokenAmount * 1e18);
        require(transferred, "transfer-failed");
        _internalTokenBalance += tokenAmount * 1e18;

        return _executeSell(msg.sender, tokenAmount, minEthOut);
    }

    function sync() external {
        _internalTokenBalance = token.balanceOf(address(this));
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

    function _executeSell(address seller, uint256 tokenAmount, uint256 minEthOut) internal returns (uint256 ethOut) {
        ethOut = quoteSell(tokenAmount);
        require(ethOut >= minEthOut, "slippage");
        require(ethOut > 0, "insufficient-liquidity");
        require(address(this).balance >= ethOut, "insufficient-liquidity");

        (bool ok, ) = seller.call{value: ethOut}("");
        require(ok, "payout-failed");

        emit TokensSold(seller, tokenAmount, ethOut);
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
        return (token.totalSupply() - _internalTokenBalance) / 1e18;
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
        revert("use-commit-buy");
    }
}
