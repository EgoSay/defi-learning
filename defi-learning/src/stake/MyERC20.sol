// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;


import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MyERC20 is ERC20("MyToken", "MTK"), Ownable(msg.sender) {

    uint256 public totalSupplyLimit;
    uint256 public perMint;
    uint256 public mintedSupply;

    function mint(address to) public onlyOwner {
        require(mintedSupply + perMint <= totalSupplyLimit, "Exceeds total supply");
        _mint(to, perMint);
        mintedSupply += perMint;
    }
}