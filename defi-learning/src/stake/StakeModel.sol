// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract StakeModel {

    address payToken;
    constructor(address _payToken) {
        payToken = _payToken;
    }
   
    uint256 public totalStakedAmount = 0;
    // nonce for dividend function
    uint256 public dividendNonces = 0; 
    // 数组记录分红配额
    // mapping(uint256 => uint256) public dividendQuotas;
    // 只需要记录当前最新的累积分红配额即可
    uint256 public latestDividendAmount = 0;

    struct StakedInfo {
        uint256 stakedAmount; // amount of tokens staked by the user
        uint256 unClaimedReward; // reward earned by the user
        uint256 lastStakedAt;  // last staked time
    }
    // mapping to track address and their staked info
    mapping(address => StakedInfo) public stakedInfos;

    function dividend(uint256 amount) internal {
        require(amount > 0, "amount must be greater than 0");
        if (totalStakedAmount == 0) {
            return;
        } else {
           latestDividendAmount += amount * 1e18 / totalStakedAmount / 1e18;
        }
    }


    function stake(uint256 amount) public payable {
        require(amount > 0, "amount must be greater than 0");
        
        _updateReward(msg.sender);
        stakedInfos[msg.sender].stakedAmount += amount;
        totalStakedAmount += amount;
        emit Stake(msg.sender, amount);
    }


     function _updateReward(address user) private {
        StakedInfo memory stakeDetails = stakedInfos[user];
        // calculate reward based on staked amount
        uint256 canGetReward = stakeDetails.stakedAmount * (latestDividendAmount - stakeDetails.lastStakedAt);
        stakeDetails.unClaimedReward += canGetReward;
        stakeDetails.lastStakedAt = latestDividendAmount;
        stakedInfos[user] = stakeDetails;
    }

    function unstake(uint256 amount) internal {
        require(amount > 0, "amount must be greater than 0");
        StakedInfo memory stakeDetails = stakedInfos[msg.sender];
        require(stakeDetails.stakedAmount >= amount, "insufficient balance");

        _updateReward(msg.sender);
        // calculate reward and decrease staked amount
        stakedInfos[msg.sender].stakedAmount -= amount;
        // transfer ether to user
        payable(msg.sender).transfer(amount);
        totalStakedAmount -= amount;
        emit Unstake(msg.sender, amount);
    }

     function claimReward() internal {
        _updateReward(msg.sender);

        uint256 unClaimedReward = stakedInfos[msg.sender].unClaimedReward;
        require(unClaimedReward > 0, "no reward to claim");
        stakedInfos[msg.sender].unClaimedReward = 0;

        // transfer reward to user
        IERC20(payToken).transfer(msg.sender, unClaimedReward);
        emit Claim(msg.sender, unClaimedReward);
    }

    function getStakeDetails(address user) public view returns (uint256, uint256) {
        StakedInfo memory stakeDetails = stakedInfos[user];
        uint256 canGetReward = stakeDetails.stakedAmount * (latestDividendAmount - stakeDetails.lastStakedAt);
        uint256 unclaimReward = canGetReward + stakeDetails.unClaimedReward;
        return (stakeDetails.stakedAmount, unclaimReward);
    }

    event Stake(address indexed from, uint256 amount);
    event Unstake(address indexed from, uint256 amount);
    event Claim(address indexed from, uint256 amount);
    event Dividend(uint256 indexed nonce, uint256 amount);
} 
