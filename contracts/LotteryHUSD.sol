// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./Lottery.sol";

/**
 * @title 4个号码的乐透彩票合约
 * 部署顺序:
 * 1.部署LotteryNFT
 * 2.部署当前合约LotteryHUSD
 * 3.设置LotteryNFT.setAdmin()
 * 操作顺序:
 * 1.购买 buy() || multiBuy()
 * 2.进入开奖阶段 enterDrawingPhase()
 * 3.开奖 drawing()
 * 4.重置 reset()
 */
contract LotteryHUSD is Lottery {
    /// @notice HUSD地址 用于购买彩票的Token
    address public constant HUSD = 0x0298c2b32eaE4da002a15f36fdf7615BEa3DA047;
    /// @notice GOC地址
    address public constant GOC = 0x271B54EBe36005A7296894F819D626161C44825C;
    /// @notice Lottery GOC地址
    address public lotteryGOC;

    /**
     * @dev 构造函数
     * @param _lotteryNFT 乐透NFT地址
     */
    constructor(ILotteryNFT _lotteryNFT, address _lotteryGOC) public Lottery(_lotteryNFT, HUSD) {
        // 设置地址
        lotteryGOC = _lotteryGOC;
        // 批准HUSD无限量
        IERC20(GOC).approve(lotteryGOC, uint256(-1));
        // 批准HUSD无限量
        IERC20(HUSD).approve(GOSWAP_ROUTER, uint256(-1));
        // 最小售价
        minPrice = 100000000;
    }

    /**
     * @dev 重置
     */
    function reset() public override onlyAdmin {
        super.reset();
        // 销毁数额 = 最后一次总奖金 * (100 - 一等奖+二等奖+三等奖)分配比例 / 100
        uint8 _allocation = uint8(uint8(100).sub(allocation[0]).sub(allocation[1]).sub(allocation[2]));
        uint256 amount = getTotalRewards(issueIndex - 1).mul(_allocation).div(100);
        // 交易路径 HUSD=>GOC
        address[] memory path = new address[](2);
        path[0] = HUSD;
        path[1] = GOC;
        // 调用路由合约用HUSD交换GOC
        Uni(GOSWAP_ROUTER).swapExactTokensForTokens(amount, uint256(0), path, address(this), block.timestamp.add(1800));
        // 当前合约的GOC余额
        uint256 GOCBalance = IERC20(GOC).balanceOf(address(this));
        // GOC余额需要大于最小价格
        if (GOCBalance >= ILottery(lotteryGOC).minPrice()) {
            // 购买GOC彩票
            ILottery(lotteryGOC).buy(GOCBalance, nullTicket);
        }
        emit Reset(issueIndex);
    }

    /**
     * @dev 设置LotteryGOC
     * @param _lotteryGOC lotteryGOC地址
     */
    function setLotteryGOC(address _lotteryGOC) external onlyOwner {
        // 如果lotteryGOC地址不为0
        if (lotteryGOC != address(0)) {
            // 取消授权
            IERC20(GOC).approve(lotteryGOC, uint256(0));
        }
        // 设置地址
        lotteryGOC = _lotteryGOC;
        // 批准HUSD无限量
        IERC20(GOC).approve(lotteryGOC, uint256(-1));
    }
}
