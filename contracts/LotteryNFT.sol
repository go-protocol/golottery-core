// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title 乐透NFT合约
 */
contract LotteryNFT is ERC721, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    struct LotteryInfo {
        uint8[4] numbers;
        uint256 amount;
        uint256 issueIndex;
        bool claimInfo;
        address owner;
    }

    /// @dev 管理员地址
    address public adminAddress;
    /// @dev TokenID => 彩票信息
    mapping(uint256 => uint8[4]) public lotteryInfo;
    /// @dev TokenID => 彩票价格
    mapping(uint256 => uint256) public lotteryAmount;
    /// @dev TokenID => 发行索引
    mapping(uint256 => uint256) public issueIndex;
    /// @dev TokenID => 是否领奖
    mapping(uint256 => bool) public claimInfo;

    constructor() public ERC721("Go Lottery GOC Ticket", "cGLT") {
        adminAddress = msg.sender;
    }

    /**
     * @dev 创建新Item
     * @param player 用户地址
     * @param _lotteryNumbers 乐透号码
     * @param _amount 购买金额
     * @param _issueIndex 发行索引
     */
    function newLotteryItem(
        address player,
        uint8[4] memory _lotteryNumbers,
        uint256 _amount,
        uint256 _issueIndex
    ) public onlyOwner returns (uint256) {
        _tokenIds.increment();

        uint256 newItemId = _tokenIds.current();
        _mint(player, newItemId);
        lotteryInfo[newItemId] = _lotteryNumbers;
        lotteryAmount[newItemId] = _amount;
        issueIndex[newItemId] = _issueIndex;
        // _setTokenURI(newItemId, tokenURI);

        return newItemId;
    }

    /**
     * @dev 获取Token全部数据
     * @param tokenId tokenId
     */
    function lotteryURI(uint256 tokenId) external view returns (LotteryInfo memory _lotteryInfo) {
        _lotteryInfo.numbers = lotteryInfo[tokenId];
        _lotteryInfo.amount = lotteryAmount[tokenId];
        _lotteryInfo.issueIndex = issueIndex[tokenId];
        _lotteryInfo.claimInfo = claimInfo[tokenId];
        _lotteryInfo.owner = ownerOf(tokenId);
    }

    /**
     * @dev 获取乐透号码
     * @param tokenId tokenId
     */
    function getLotteryNumbers(uint256 tokenId) external view returns (uint8[4] memory) {
        return lotteryInfo[tokenId];
    }

    /**
     * @dev 获取购买数额
     * @param tokenId tokenId
     */
    function getLotteryAmount(uint256 tokenId) external view returns (uint256) {
        return lotteryAmount[tokenId];
    }

    /**
     * @dev 获取发行索引
     * @param tokenId tokenId
     */
    function getLotteryIssueIndex(uint256 tokenId) external view returns (uint256) {
        return issueIndex[tokenId];
    }

    /**
     * @dev 领奖
     * @param tokenId tokenId
     */
    function claimReward(uint256 tokenId) external onlyOwner {
        claimInfo[tokenId] = true;
    }

    /**
     * @dev 批量领取
     * @param tokenIds tokenId数组
     */
    function multiClaimReward(uint256[] memory tokenIds) external onlyOwner {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            claimInfo[tokenIds[i]] = true;
        }
    }

    /**
     * @dev 销毁token
     * @param tokenId tokenId
     */
    function burn(uint256 tokenId) external onlyOwner {
        _burn(tokenId);
    }

    /**
     * @dev 获取领奖状态
     * @param tokenId tokenId
     */
    function getClaimStatus(uint256 tokenId) external view returns (bool) {
        return claimInfo[tokenId];
    }

    /**
     * @dev 通过之前的开发者更新管理员地址
     * @param _adminAddress 管理员地址
     */
    function setAdmin(address _adminAddress) external {
        require(msg.sender == adminAddress, "admin: wut?");
        adminAddress = _adminAddress;
    }

    /**
     * @dev 设置TokenURI
     * @param tokenId tokenId
     * @param _tokenURI TokenURI地址
     */
    function setTokenURI(uint256 tokenId, string memory _tokenURI) external {
        require(msg.sender == adminAddress, "admin: wut?");
        _setTokenURI(tokenId, _tokenURI);
    }

    /**
     * @dev 设置BaseURI
     * @param baseURI_ BaseURI地址
     */
    function setBaseURI(string memory baseURI_) external {
        require(msg.sender == adminAddress, "admin: wut?");
        _setBaseURI(baseURI_);
    }
}
