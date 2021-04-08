// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./Lottery.sol";

/**
 * @title 4个号码的乐透彩票合约
 * 部署顺序:
 * 1.部署LotteryNFT
 * 2.部署当前合约LotteryGOC
 * 3.设置LotteryNFT.setAdmin()
 * 4.设置GOT.addAdmin()
 * 操作顺序:
 * 1.购买 buy() || multiBuy()
 * 2.进入开奖阶段 enterDrawingPhase()
 * 3.开奖 drawing()
 * 4.重置 reset()
 */
contract LotteryGOC is Lottery {
    /// @notice GOT地址
    address public constant GOT = 0xA7d5b5Dbc29ddef9871333AD2295B2E7D6F12391;
    /// @notice GOC地址 用于购买彩票的Token
    address public constant GOC = 0x271B54EBe36005A7296894F819D626161C44825C;

    /**
     * @dev 构造函数
     * @param _lotteryNFT 乐透NFT地址
     */
    constructor(ILotteryNFT _lotteryNFT) public Lottery(_lotteryNFT, GOC) {
        // 批准GOC无限量
        IERC20(GOC).approve(GOSWAP_ROUTER, uint256(-1));
        // 最小售价
        minPrice = 1000000000000000000;
    }

    /**
     * @dev 重置
     */
    function reset() public override onlyAdmin {
        super.reset();
        // 销毁数额 = 最后一次总奖金 * (100 - 一等奖+二等奖+三等奖)分配比例 / 100
        uint8 burnAllocation = uint8(uint8(100).sub(allocation[0]).sub(allocation[1]).sub(allocation[2]));
        uint256 burnAmount = getTotalRewards(issueIndex - 1).mul(burnAllocation).div(100);
        if (burnAmount > 0) {
            // 交易路径 GOC=>GOT
            address[] memory path = new address[](2);
            path[0] = GOC;
            path[1] = GOT;
            // 调用路由合约用GOC交换GOT
            Uni(GOSWAP_ROUTER).swapExactTokensForTokens(burnAmount, uint256(0), path, address(this), block.timestamp.add(1800));
        }
        // 当前合约的GOT余额
        uint256 GOTBalance = IERC20(GOT).balanceOf(address(this));
        if (GOTBalance > 0) {
            // 销毁GOT
            IGOT(GOT).burn(GOTBalance);
        }
    }
}
