// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20Permit, EIP712, ERC20, Nonces} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {console} from "forge-std/console.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {StakeModel} from "./StakeModel.sol";


contract StakeNFTMarket is EIP712("StakeNFTMarket", "1"), Ownable(msg.sender), StakeModel {
    using ECDSA for bytes32;

    constructor (address _whitelistSigner, address _feeTo, address _payToken) StakeModel(_payToken) {
        whitelistSigner = _whitelistSigner;
        feeTo = _feeTo;
    }

    // define nft sale info
    struct NftOrderInfo {
        address seller;  // nft seller
        address nftContract; // nft contract address
        // address payToken;  // pay token
        uint256 tokenId;  // nft token id
        uint256 price;  // nft price
        uint256 deadline;  // order deadline
    }
    // Mapping to track the nft orderId id to NftOrderInfo
    mapping(bytes32 => NftOrderInfo) public nftOrders;
    //  nft -> lastOrderId
    mapping(address => mapping(uint256 => bytes32)) private _lastIds; 


    // 项目方，也就是白名单签署方
    address public whitelistSigner;
    address public constant ETH_FLAG = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    address public feeTo;
    uint256 public constant feeBP = 30; // 30/10000 = 0.3%

    /*
     * @description: add nft to the market list
     */    
    function list(address nftContract, 
                uint256 tokenId, 
                uint256 price, 
                uint256 deadline, 
                bytes calldata signatureForSellOrder
            ) external returns (bool) {
        
        require(price > 0, "PermitNFTMarket: nft price must greater than 0");
        require(payToken == address(0) || IERC20(payToken).totalSupply() > 0, "MKT: payToken is not valid");
        require(deadline > block.timestamp, "PermitNFTMarket: deadline is expired");


        NftOrderInfo memory order = NftOrderInfo({
            seller: msg.sender,
            nftContract: nftContract,
            payToken: payToken,
            tokenId: tokenId,
            price: price,
            deadline: deadline
        });
        bytes32 orderId = keccak256(abi.encode(order));

        // nft owner 需要签名，授权 nftMarket 上架 nft 信息
        _nftPermit(order, signatureForSellOrder);

        // check the operator permission 
        address owner = IERC721(nftContract).ownerOf(tokenId);
        require(msg.sender == owner, "PermitNFTMarket: not nft owner");
        require(
            IERC721(nftContract).getApproved(tokenId) == address(this)
                || IERC721(nftContract).isApprovedForAll(msg.sender, address(this)),
            "PermitNFTMarket: not approved"
        );

        // safe check repeat list
        require(nftOrders[orderId].seller == address(0), "PermitNFTMarket: order already listed");
        // save the order info
        _lastIds[nftContract][tokenId] = orderId;
        nftOrders[orderId] = order;
        emit NFTListed(nftContract, tokenId, orderId, msg.sender, payToken, price, deadline);
        return true;
    }


    /*
     * @description: cacel the nfs list order
     * @param {bytes32} orderId 
     */    
    function cancelOrder(bytes32 orderId) external {
        address seller = nftOrders[orderId].seller;
        // safe check repeat list
        require(seller != address(0), "PermitNFTMarket: order not listed");
        require(seller == msg.sender, "PermitNFTMarket: only seller can cancel");
        delete nftOrders[orderId];
        emit Cancel(orderId);
    }

    // buy with eth and no fee
    function buy(bytes32 orderId) public payable {
        _buy(orderId, feeTo);
    }

    /*
     * @description: private buy operation
     * @param {bytes32} orderId  => abi.encode(NftOrderInfo)
     * @param {address} feeReceiver 
     * @return {*}
     */    
    function _buy(bytes32 orderId, address feeReceiver) private {
        // 1. check the order is exist and valid
        NftOrderInfo memory order = nftOrders[orderId];
        require(order.seller != address(0), "PermitNFTMarket: order not listed");
        require(order.deadline > block.timestamp, "PermitNFTMarket: order is expired");
        
        // delete order info before transfer to avoid reentrancy
        delete nftOrders[orderId];

        // 2. transfer nft to the buyer
        IERC721(order.nftContract).safeTransferFrom(order.seller, msg.sender, order.tokenId);
        console.log("transfer nft success");
        // 3. transfer fee to the fee receiver
        uint256 fee = feeReceiver == address(0) ? 0 : order.price * feeBP / 10000;
        // safe check
        if (order.payToken == ETH_FLAG) {
            require(msg.value == order.price, "PermitNFTMarket: wrong eth value");
        } else {
            require(msg.value == 0, "PermitNFTMarket: wrong eth value");
        }
        if (fee > 0) _transferOut(order.payToken, msg.sender, feeReceiver, fee);

        // 执行分红
        if (fee > 0) {
            dividend(fee);
        }

        // transfer the rest to the seller
        uint256 sellPrice = order.price - fee;
        _transferOut(order.payToken, msg.sender, order.seller, sellPrice);
        emit NFTBought(msg.sender, order.nftContract, order.tokenId, order.price);
    }

    function _transferOut(address token, address from, address to, uint256 amount) private {
        if (token == ETH_FLAG) {
            // TODO 这样只能从 market 转 eth 到 seller, 而不是从 buyer 直接转账到 seller
            payable(to).transfer(amount);
        } else {
            IERC20(token).transferFrom(from, to, amount);
        }
    }


    function permitBuy(
        address nft, uint256 tokenId,
        bytes calldata signatureForWL,
        bytes calldata signatureForSellOrder,
        bytes calldata signatureForApprove
    ) public returns (bool) {
        // find the nft order id
        bytes32 orderId = listing(nft, tokenId);
        require(orderId != bytes32(0), "PermitNFTMarket: order not listed");
        NftOrderInfo memory nftOrder = nftOrders[orderId];
        
        _verifyWL(signatureForWL);

          // nft owner 需要签名，授权 nftMarket 出售 nft 信息
        _nftPermit(nftOrder, signatureForSellOrder);

        _tokenPermit(nftOrder, signatureForApprove);

        _buy(orderId, address(0));
        
        return true;

    }


    bytes32 public constant WL_TYPEHASH =
        keccak256("PermitNFTWhiteList(address wlSigner, address user)");
    function _verifyWL (bytes calldata signatureForWL) view private {
        // 检查白名单签名
        bytes32 wlDigest = _hashTypedDataV4(
            keccak256(abi.encode(WL_TYPEHASH, whitelistSigner, address(msg.sender)))
        );
        console.logBytes32(wlDigest);
        address wlSigner = ECDSA.recover(wlDigest, signatureForWL);
        require(wlSigner == whitelistSigner, "You are not in WL");
        console.log("wl  check is ok");
    }

    function _nftPermit(NftOrderInfo memory nftOrder, bytes calldata signatureForSellOrder) private {
        // 检查上架信息是否存在， [检查后为了防止重入，删除上架信息]
        require(nftOrder.seller != address(0), "nft not on sale");

        // nft 签名授权
        (bytes32 r, bytes32 s, uint8 v) = decodeSign(signatureForSellOrder);
        // PermitNFT(nftOrder.nftContract).permit(nftOrder.tokenId, address(this), nftOrder.deadline, v, r, s);
        (bool result, ) = (nftOrder.nftContract).call(
                abi.encodeWithSignature("permit(uint256,address,uint256,uint8,bytes32,bytes32)",
                nftOrder.tokenId, 
                address(this), 
                nftOrder.deadline, 
                v, r, s
            )
        );
        require(result, "nft permit failed");
    }


     function _tokenPermit(
        NftOrderInfo memory nftOrder,
        bytes memory signatureForApprove) private {
        // 执行 ERC20 的 permit 进行 授权
        (bytes32 r, bytes32 s, uint8 v) = decodeSign(signatureForApprove);
        IERC20Permit(nftOrder.payToken).permit(msg.sender, address(this), nftOrder.price, nftOrder.deadline, v, r, s);
     }
     
    function getHashData(bytes32 structHash) public view returns (bytes32) {
        return _hashTypedDataV4(structHash);
    }

    function decodeSign(bytes memory signature) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }
        return (r, s, v);
    }

    // admin functions
    function setWhiteListSigner(address signer) external onlyOwner {
        require(signer != address(0), "MKT: zero address");
        require(whitelistSigner != signer, "MKT:repeat set");
        whitelistSigner = signer;

        emit SetWhiteListSigner(signer);
    }

    function setFeeTo(address to) external onlyOwner {
        require(feeTo != to, "MKT:repeat set");
        feeTo = to;

        emit SetFeeTo(to);
    }

    function listing(address nft, uint256 tokenId) public view returns (bytes32) {
        bytes32 id = _lastIds[nft][tokenId];
        return nftOrders[id].seller == address(0) ? bytes32(0x00) : id;
    }

      function getPermitTypehash() public pure returns (bytes32) {
        return WL_TYPEHASH;
    }

      // event to log nft trade record
    event NFTListed(
        address indexed nft, // 
        uint256 indexed tokenId,
        bytes32 orderId,
        address seller,
        address payToken,
        uint256 price,
        uint256 deadline
    );
    event NFTBought(address indexed buyer, address indexed nftContract, uint256 indexed tokenId, uint256 price);
    event Cancel(bytes32 orderId);
    event SetFeeTo(address indexed feeReceiver);
    event SetWhiteListSigner(address indexed signer);

}