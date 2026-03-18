// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {DAOGovernanceToken} from "./DAOGovernanceToken.sol";

contract DAOTokenMarket is Ownable, ReentrancyGuard {
    DAOGovernanceToken public immutable token;

    struct CommitInfo {
        bytes32 commitHash;
        uint256 blockNumber;
        bool used;
    }

    uint256 public constant COMMIT_MIN_DELAY = 1;
    uint256 public constant COMMIT_MAX_AGE = 256;

    uint256 public basePriceWei;
    uint256 public slopeWei;

    uint256 private _trackedTokenBalance;

    mapping(address => CommitInfo) public commitments;

    event TokensPurchased(address indexed buyer, uint256 ethSpent, uint256 tokensMinted);
    event TokensSold(address indexed seller, uint256 tokensSold, uint256 ethReceived);
    event CurveParamsUpdated(uint256 basePriceWei, uint256 slopeWei);
    event Committed(address indexed committer, bytes32 commitHash);
    event TokensSkimmed(address indexed to, uint256 amount);

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

    function commit(bytes32 hash) external {
        commitments[msg.sender] = CommitInfo({commitHash: hash, blockNumber: block.number, used: false});
        emit Committed(msg.sender, hash);
    }

    function buy(uint256 minTokensOut, bytes32 salt) external payable nonReentrant returns (uint256 tokensOut) {
        _consumeCommitment(keccak256(abi.encodePacked("buy", msg.value, minTokensOut, salt)));
        return _buy(msg.sender, msg.value, minTokensOut);
    }

    function sell(uint256 tokenAmount, uint256 minEthOut, bytes32 salt) external nonReentrant returns (uint256 ethOut) {
        require(tokenAmount > 0, "amount=0");

        _consumeCommitment(keccak256(abi.encodePacked("sell", tokenAmount, minEthOut, salt)));

        ethOut = quoteSell(tokenAmount);
        require(ethOut >= minEthOut, "slippage");
        require(ethOut > 0, "insufficient-liquidity");
        require(address(this).balance >= ethOut, "insufficient-liquidity");

        uint256 transferAmount = tokenAmount * 1e18;
        bool transferred = token.transferFrom(msg.sender, address(this), transferAmount);
        require(transferred, "transfer-failed");
        _trackedTokenBalance += transferAmount;

        (bool ok, ) = msg.sender.call{value: ethOut}("");
        require(ok, "payout-failed");

        emit TokensSold(msg.sender, tokenAmount, ethOut);
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

    function skim(address to) external onlyOwner {
        require(to != address(0), "to=0");

        uint256 actualBalance = token.balanceOf(address(this));
        uint256 excessBalance = actualBalance - _trackedTokenBalance;
        require(excessBalance > 0, "nothing-to-skim");

        bool transferred = token.transfer(to, excessBalance);
        require(transferred, "skim-failed");

        emit TokensSkimmed(to, excessBalance);
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
        return (token.totalSupply() - _trackedTokenBalance) / 1e18;
    }

    function _consumeCommitment(bytes32 expectedHash) internal {
        CommitInfo storage info = commitments[msg.sender];

        require(info.commitHash != bytes32(0), "commit-missing");
        require(!info.used, "commit-used");

        uint256 age = block.number - info.blockNumber;
        require(age >= COMMIT_MIN_DELAY, "commit-too-soon");
        require(age <= COMMIT_MAX_AGE, "commit-expired");
        require(info.commitHash == expectedHash, "commit-mismatch");

        info.used = true;
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
