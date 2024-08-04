
# Task:
升级 NFTMarket 合约，每次 nft 交易成功可以按一定比例抽取手续费进行分红，所有用户可以选择质押 eth 至 NFTMarket，获取分红

## 实现

质押逻辑单独抽离出来作为一个合约模型，NFTMarket 继承质押合约实现质押分红逻辑

- [质押合约逻辑](./src/stake/StakeModel.sol)
- [NFTMarket 合约](./src/stake/NFTMarket.sol)

## 测试用例
- [StakeNFTMarket.t.sol](./test/StakeNFTMarket.t.sol)

## 测试结果
- [StakeNFTMarketTest.log](./test/StakeNFTMarketTest.log)