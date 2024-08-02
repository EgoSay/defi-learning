// // SPDX-License-Identifier: SEE LICENSE IN LICENSE
// pragma solidity ^0.8.20;


// import {console, StdCheats, Test} from "forge-std/Test.sol";
// import {MyERC20Token} from "../src/stake/MyERC20Token.sol";
// import {StakeNFTMarket} from "../src/stake/StakeNFTMarket.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// contract StakeNFTMarketTest is Test {
    
//     MyERC20Token token;
//     StakeNFTMarket market;
//     address alice = makeAddr("alice");

//     function setUp() public {

//         token = new MyERC20Token();
//         market = new StakeNFTMarket();

//         token.mint(alice, 1000 * 1e18);
//     }

//     function testDealNFTAndStake() public {
//         // user  A stake some ether
//         address alice = makeAddr("alice");


//         // deal an nft trade

//         // user B stake some ether

//         // user A claim reward, and assert the reward is correct

//         // user C stake some ether

//         // user B unstake, and assert the reward is correct
//     }

//     function dealNFT() private view {
//          // nft owner 签名授权 nftMarket 上架出售
//         (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(sellerPrivateKey, getSignatureForNft());
//         bytes memory signatureForNft = abi.encodePacked(r2, s2, v2);

//         // 上架 nft
//         vm.startPrank(seller);
//         bool listedRsult = market.list(address(nftContract), 
//                             nftOwnerMap[seller], 
//                             address(token), 
//                             nftDeafultPrice, 
//                             deadline, 
//                             signatureForNft);
//         assertTrue(listedRsult);
//         vm.stopPrank();

//         bytes32 whiteListDigest = keccak256(abi.encode(
//                     nftContract.getPermitTypehash(),
//                     seller,
//                     address(market),
//                     address(nftContract),
//                     tokenId,
//                     deadline
//             ));
//         (uint8 v1, bytes32 r1, bytes32 s1) =vm.sign(whitelistSignerPrivateKey, getSignatureForWL());
//         bytes memory signatureForWL = abi.encodePacked(r1, s1, v1);

//         (uint8 v3, bytes32 r3, bytes32 s3) = vm.sign(buyerPrivateKey, getSignatureForTokenApprove());
//         bytes memory signatureForApprove = abi.encodePacked(r3, s3, v3);

//         // buyer 执行购买
//         doPermitBuy(signatureForWL, signatureForNft, signatureForApprove);

//         // 验证 nft owner 是否转移
//         assertEq(buyer, nftContract.ownerOf(nftOwnerMap[seller]));
//         // 验证 user 和 buyer 余额 token 是否正确
//         assertEq(token.balanceOf(buyer), (init_price - nftDeafultPrice));
//         assertEq(token.balanceOf(seller), (nftDeafultPrice));
//     }
// }