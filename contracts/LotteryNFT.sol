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

    constructor() public ERC721("Go Lottery Ticket", "GLT") {
        adminAddress = msg.sender;
    }

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
        // claimInfo[newItemId] = false; default is false here
        // _setTokenURI(newItemId, tokenURI);

        return newItemId;
    }

    function getLotteryNumbers(uint256 tokenId) external view returns (uint8[4] memory) {
        return lotteryInfo[tokenId];
    }

    function getLotteryAmount(uint256 tokenId) external view returns (uint256) {
        return lotteryAmount[tokenId];
    }

    function getLotteryIssueIndex(uint256 tokenId) external view returns (uint256) {
        return issueIndex[tokenId];
    }

    function claimReward(uint256 tokenId) external onlyOwner {
        claimInfo[tokenId] = true;
    }

    function multiClaimReward(uint256[] memory tokenIds) external onlyOwner {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            claimInfo[tokenIds[i]] = true;
        }
    }

    function burn(uint256 tokenId) external onlyOwner {
        _burn(tokenId);
    }

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

    function setTokenURI(uint256 tokenId, string memory _tokenURI) external {
        require(msg.sender == adminAddress, "admin: wut?");
        _setTokenURI(tokenId, _tokenURI);
    }

    function setBaseURI(string memory baseURI_) external {
        require(msg.sender == adminAddress, "admin: wut?");
        _setBaseURI(baseURI_);
    }
}
