pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract LiquidityPool is ERC20 {
    constructor() ERC20("LiquidityPool", "LQ") { }

    address public token1;
    address public token2;

    uint256 public reserve1;
    uint256 public reserve2;
    uint256 public totalLiquidity;

    

}