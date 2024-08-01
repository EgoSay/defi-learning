// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;


import {console, StdCheats, Test} from "forge-std/Test.sol";
import {MyERC20} from "../src/stake/MyERC20.sol";
import {StakeNFTMarket} from "../src/stake/StakeNFTMarket.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract StakeNFTMarketTest is Test {
    
    MyERC20 token;
    StakeNFTMarket market;
    address alice = makeAddr("alice");

    function setUp() public {

        token = new MyERC20();
        market = new StakeNFTMarket();

        token.mint(alice, 1000 * 1e18);
    }

    function testDealNFTAndStake() public {
        // 
    }
}