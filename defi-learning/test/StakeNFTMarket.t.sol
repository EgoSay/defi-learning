// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;


import {console, StdCheats, Test} from "forge-std/Test.sol";
import {MyERC20Token} from "../src/stake/MyERC20Token.sol";
import {MyNFT} from "../src/stake/MyNFT.sol";
import {StakeNFTMarket} from "../src/stake/StakeNFTMarket.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract StakeNFTMarketTest is Test {
    
    MyERC20Token token;
    StakeNFTMarket market;
    MyNFT nftContract;

    address admin = makeAddr("admin");

    uint256 defaultAmount = 1e18;

    function setUp() public {
        vm.startPrank(admin);
        token = new MyERC20Token();
        market = new StakeNFTMarket(address(token));
        nftContract = new MyNFT();
        vm.stopPrank();
    }

    function testDealNFTAndStake() public {
        // A staked 1e18 and unclaim reward 4e18
        // B staked 2e18 and unclaim reward 2e18
        _dealNFTAndStake();
    }

    function testStakeAndClaim() public {
        // A staked 1e18 and unclaim reward 4e18
        // B staked 2e18 and unclaim reward 2e18
        uint256 totalStaked = _dealNFTAndStake();
        // user C stake 3e18 ether, the totalStaked = 6e18
        address caro = makeAddr("caro"); 
        initUserInfoAndStake(caro, defaultAmount * 3);
        totalStaked += defaultAmount;
        uint256 nftPrice = 2000e18;

        // deal an nft trade
        _dealNFT(makeAddr("seller3"), nftPrice);

        // c unstaked 1e18 and claim reward
        vm.startPrank(caro);
        market.unstake(defaultAmount);
        (uint256 caroStakedAmount, uint256 caroReward) = market.getStakeDetails(caro);
        assertEq(caroStakedAmount, defaultAmount * 2);

        uint256 expectedReward = (nftPrice * market.feeBP() / market.feeRate()) * caroStakedAmount / totalStaked;
        assertEq(caroReward, expectedReward);
        vm.expectEmit(true, true, false, false);
        emit Claim(caro, expectedReward);
        market.claimReward();
        vm.stopPrank();
        
    }


    function _dealNFTAndStake() private returns(uint256){
        uint256 totalStaked = 0;
        // user  A stake some ether
        address alice = makeAddr("alice"); 
        initUserInfoAndStake(alice, defaultAmount);
        totalStaked += defaultAmount;

        // deal an nft trade
        uint256 nftPrice = 1000e18;
        _dealNFT(makeAddr("seller1"), nftPrice);

        // assert the reward is correct
        (uint256 aliceStakedAmount, uint256 aliceReward) = market.getStakeDetails(alice);
        uint256 expectedReward = nftPrice * market.feeBP() / market.feeRate();
        assertEq(aliceStakedAmount, defaultAmount);
        assertEq(aliceReward, expectedReward);

        // user B stake some ether
        address bob = makeAddr("bob"); 
        initUserInfoAndStake(bob, defaultAmount * 2);
        totalStaked += defaultAmount * 2;

        // total fees: 3 + 3 = 6
        _dealNFT(makeAddr("seller2"), nftPrice);
        uint256 reward2 = nftPrice * market.feeBP() / market.feeRate();
        (uint256 aliceStakedAmount2, uint256 aliceReward2) = market.getStakeDetails(alice);
        uint256 expectedReward2 = expectedReward + reward2 * aliceStakedAmount2 / totalStaked;
        assertEq(aliceStakedAmount2, defaultAmount);
        assertEq(aliceReward2, expectedReward2);

        (uint256 bobStakedAmount, uint256 bobReward) = market.getStakeDetails(bob);
        assertEq(bobStakedAmount, defaultAmount * 2);
        assertEq(bobReward, reward2 * bobStakedAmount / totalStaked);

        return totalStaked;
    }

    function initUserInfoAndStake(address user, uint256 balance) private {
        deal(user, balance);
        vm.startPrank(user);
        token.approve(address(market), balance);
        market.stake{value: balance}(balance);
        vm.stopPrank();
    }

    function _dealNFT(address seller, uint256 nftPrice ) private {
        // 创建 nft
        vm.prank(admin);
        uint256 tokenId = nftContract.mint(seller, "");

        // 上架 nft
        uint256 deadline = block.timestamp + 1 days;
        vm.startPrank(seller);
        nftContract.approve(address(market), tokenId);
        bool listedRsult = market.list(address(nftContract), tokenId, nftPrice, deadline);
        assertTrue(listedRsult);
        vm.stopPrank();

        // uint256 buyerBalance = 2000e18;
        address buyer = _doBuyNFT(nftPrice, deadline, tokenId);

        // 验证 nft owner 是否转移
        assertEq(buyer, nftContract.ownerOf(tokenId));
        // 验证 user 和 buyer 余额 token 是否正确
        assertEq(token.balanceOf(buyer), 0);
    }

    function _doBuyNFT(uint256 nftPrice, uint256 deadline, uint256 tokenId) private returns (address) {
        uint256 buyerPrivateKey = 0xB1111;
        address buyer = vm.addr(buyerPrivateKey);
        deal(address(token), buyer, nftPrice);
        deal(buyer, nftPrice);
        vm.startPrank(buyer);
        uint256 nonce = token.nonces(buyer);
        // 签名
        bytes32 tokenDigiest = token.getHashData(
                keccak256(abi.encode(
                    token.getPermitTypehash(),
                    buyer,
                    address(market),
                    nftPrice,
                    nonce,
                    deadline
                ))
            );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(buyerPrivateKey, tokenDigiest);
        // buyer 执行购买
        bool buyResult = market.permitBuy(address(nftContract), tokenId, r, s, v);
        assertTrue(buyResult);
        vm.stopPrank();
        return buyer;
    }

    event Claim(address indexed from, uint256 indexed amount);

}