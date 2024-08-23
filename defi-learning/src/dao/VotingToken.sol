// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

contract VotingToken is ERC20Votes {
    constructor(string memory name_, string memory symbol_, uint256 initialSupply) ERC20(name_, symbol_) EIP712(name_, "1") {
        _mint(msg.sender, initialSupply);
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);    
    }

 
     function burn(address account, uint256 amount) public {
        super._burn(account, amount);
     }
}
