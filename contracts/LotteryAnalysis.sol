// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

interface ILottery {
    function getUserInfo(address) external view returns (uint256[] memory);

    function getRewardView(uint256 _tokenId) external view returns (uint256);

    function lotteryNFT() external view returns (address);
}

interface INFT {
    function issueIndex(uint256) external view returns (uint256);

    function getLotteryNumbers(uint256 tokenId) external view returns (uint8[4] memory);

    function getLotteryIssueIndex(uint256 tokenId) external view returns (uint256);

    function getClaimStatus(uint256 tokenId) external view returns (bool);

    function getLotteryAmount(uint256 tokenId) external view returns (uint256);
}

contract LotteryAnalysis {
    address public constant Lottery_HUSD = 0xc881B2870b891B70bDFE9B426c7fb524fFC1F7C1;
    address public constant Lottery_GOC = 0xA4Cd00DE7138841F0eFaF3c94202270672Bf9291;

    /**
     * @dev 获取用户所有NFT
     * @param _user 用户地址
     * @return _tickets NFT Token ID
     * @return _issueIndex 发行索引
     * @return _claimed 是否领奖
     * @return _reward 奖金
     */
    function getUserGOCTickets(address _user)
        public
        view
        returns (
            uint256[] memory _tickets,
            uint256[] memory _issueIndex,
            bool[] memory _claimed,
            uint256[] memory _reward,
            uint256[] memory _amount
        )
    {
        _tickets = ILottery(Lottery_GOC).getUserInfo(_user);
        _issueIndex = new uint256[](_tickets.length);
        _claimed = new bool[](_tickets.length);
        _reward = new uint256[](_tickets.length);
        _amount = new uint256[](_tickets.length);
        address NFT_GOC = ILottery(Lottery_GOC).lotteryNFT();
        for (uint256 i = 0; i < _tickets.length; i++) {
            _issueIndex[i] = INFT(NFT_GOC).getLotteryIssueIndex(_tickets[i]);
            _claimed[i] = INFT(NFT_GOC).getClaimStatus(_tickets[i]);
            _reward[i] = ILottery(Lottery_GOC).getRewardView(_tickets[i]);
            _amount[i] = INFT(NFT_GOC).getLotteryAmount(_tickets[i]);
        }
    }

    /**
     * @dev 获取用户所有NFT
     * @param _user 用户地址
     * @return _tickets NFT Token ID
     * @return _issueIndex 发行索引
     * @return _claimed 是否领奖
     * @return _reward 奖金
     */
    function getUserHUSDTickets(address _user)
        public
        view
        returns (
            uint256[] memory _tickets,
            uint256[] memory _issueIndex,
            bool[] memory _claimed,
            uint256[] memory _reward,
            uint256[] memory _amount
        )
    {
        _tickets = ILottery(Lottery_HUSD).getUserInfo(_user);
        _issueIndex = new uint256[](_tickets.length);
        _claimed = new bool[](_tickets.length);
        _reward = new uint256[](_tickets.length);
        _amount = new uint256[](_tickets.length);
        address NFT_HUSD = ILottery(Lottery_HUSD).lotteryNFT();
        for (uint256 i = 0; i < _tickets.length; i++) {
            _issueIndex[i] = INFT(NFT_HUSD).getLotteryIssueIndex(_tickets[i]);
            _claimed[i] = INFT(NFT_HUSD).getClaimStatus(_tickets[i]);
            _reward[i] = ILottery(Lottery_HUSD).getRewardView(_tickets[i]);
            _amount[i] = INFT(NFT_HUSD).getLotteryAmount(_tickets[i]);
        }
    }

    /**
     * @dev 获取用户所有彩票号码
     * @param _tickets NFT Token ID数组
     * @return _numbers 彩票号码数组
     */
    function getGOCLotteryNumbers(uint256[] memory _tickets) public view returns (uint8[4][] memory _numbers) {
        _numbers = new uint8[4][](_tickets.length);
        address NFT_GOC = ILottery(Lottery_GOC).lotteryNFT();
        for (uint256 i = 0; i < _tickets.length; i++) {
            _numbers[i] = INFT(NFT_GOC).getLotteryNumbers(_tickets[i]);
        }
    }

    /**
     * @dev 获取用户所有彩票号码
     * @param _tickets NFT Token ID数组
     * @return _numbers 彩票号码数组
     */
    function getHUSDLotteryNumbers(uint256[] memory _tickets) public view returns (uint8[4][] memory _numbers) {
        _numbers = new uint8[4][](_tickets.length);
        address NFT_HUSD = ILottery(Lottery_HUSD).lotteryNFT();
        for (uint256 i = 0; i < _tickets.length; i++) {
            _numbers[i] = INFT(NFT_HUSD).getLotteryNumbers(_tickets[i]);
        }
    }
}
