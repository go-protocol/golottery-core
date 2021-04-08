// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./ILotteryNFT.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// import "@nomiclabs/buidler/console.sol";
interface Uni {
    function swapExactTokensForTokens(
        uint256,
        uint256,
        address[] calldata,
        address,
        uint256
    ) external;
}

interface IGOT {
    function burn(uint256 amount) external;
}

interface ILottery {
    function buy(uint256 _price, uint8[4] calldata _numbers) external;

    function minPrice() external returns (uint256);
}

/**
 * @title 4个号码的乐透彩票合约
 * @notice 4个号码必须按顺序匹配
 */
contract Lottery is Ownable {
    using SafeMath for uint256;
    using SafeMath for uint8;
    using SafeERC20 for IERC20;

    /// @dev 号码组合的索引值,固定为11,因为4个号码有11种中奖组合
    uint8 constant keyLengthForEachBuy = 11;
    /// @dev 分配第一/第二/第三奖励
    uint8[3] public allocation;
    /// @dev 乐透NFT地址
    ILotteryNFT public lotteryNFT;
    /// @dev 管理员地址
    address public adminAddress;
    /// @dev 最大数字
    uint8 public maxNumber = 14;
    /// @dev 最低售价，如果小数点不为18，请重设
    uint256 public minPrice;
    /// @notice GoSwap路由地址
    address public constant GOSWAP_ROUTER = 0xB88040A237F8556Cf63E305a06238409B3CAE7dC;
    /// @notice 购买彩票的Token
    address public token;

    // =================================

    /// @dev 发行ID => 中奖号码[numbers]
    mapping(uint256 => uint8[4]) public historyNumbers;
    /// @dev 发行ID => [tokenId]
    mapping(uint256 => uint256[]) public lotteryInfo;
    /// @dev 发行ID => [总金额, 一等奖奖金, 二等奖奖金, 三等奖奖金]
    mapping(uint256 => uint256[]) public historyAmount;
    /// @dev 发行ID => 彩票号码 => 总销量 用户购买总数额
    mapping(uint256 => mapping(uint64 => uint256)) public userBuyAmountSum;
    /// @dev 地址 => [tokenId]
    mapping(address => uint256[]) public userInfo;

    /// @dev 发行索引
    uint256 public issueIndex = 0;
    /// @dev 地址总数
    uint256 public totalAddresses = 0;
    /// @dev 总奖池数额
    uint256 public totalAmount = 0;
    /// @dev 最后时间戳
    uint256 public lastTimestamp;

    /// @dev 中奖号码
    uint8[4] public winningNumbers;

    /// @dev 开奖阶段
    bool public drawingPhase;

    // =================================

    event Buy(address indexed user, uint256 tokenId);
    event Drawing(uint256 indexed issueIndex, uint8[4] winningNumbers);
    event Claim(address indexed user, uint256 tokenid, uint256 amount);
    event DevWithdraw(address indexed user, uint256 amount);
    event Reset(uint256 indexed issueIndex);
    event MultiClaim(address indexed user, uint256 amount);
    event MultiBuy(address indexed user, uint256 amount);

    /**
     * @dev 构造函数
     * @param _lotteryNFT 乐透NFT地址
     * @param _token 购买彩票的Token
     */
    constructor(ILotteryNFT _lotteryNFT, address _token) public {
        lotteryNFT = _lotteryNFT;
        adminAddress = msg.sender;
        lastTimestamp = block.timestamp;
        allocation = [50, 30, 10];
        token = _token;
    }

    /**
     * @dev 获取历史中奖号码
     * @param _issueIndex 发行索引
     * @return _numbers 中奖号码数组
     */
    function getHistoryNumbers(uint256 _issueIndex) public view returns (uint8[4] memory _numbers) {
        _numbers = historyNumbers[_issueIndex];
    }

    /**
     * @dev 根据发行id获取NFT Token ID
     * @param _issueIndex 发行索引
     * @return _tokenId NFT Token ID
     */
    function getLotteryInfo(uint256 _issueIndex) public view returns (uint256[] memory _tokenId) {
        _tokenId = lotteryInfo[_issueIndex];
    }

    /**
     * @dev 获取历史中奖金额
     * @param _issueIndex 发行索引
     * @return _amount 中奖金额
     */
    function getHistoryAmount(uint256 _issueIndex) public view returns (uint256[] memory _amount) {
        _amount = historyAmount[_issueIndex];
    }

    /**
     * @dev 获取用户所有NFT
     * @param _user 用户地址
     * @return _tokenId NFT Token ID
     */
    function getUserInfo(address _user) public view returns (uint256[] memory _tokenId) {
        _tokenId = userInfo[_user];
    }

    /// @dev 空票
    uint8[4] internal nullTicket = [0, 0, 0, 0];

    /// @dev 只能通过管理员访问
    modifier onlyAdmin() {
        require(msg.sender == adminAddress, "admin: wut?");
        _;
    }

    /// @dev 开奖后
    function drawed() public view returns (bool) {
        // 返回第一个中奖号码
        return winningNumbers[0] != 0;
    }

    /**
     * @dev 重置
     */
    function reset() public virtual {
        // 确认开奖后
        require(drawed(), "drawed?");
        // 最后时间戳=当前区块时间戳
        lastTimestamp = block.timestamp;
        // 总地址数=0
        totalAddresses = 0;
        // 总奖池数额 = 0
        totalAmount = 0;
        // 中奖号码归零
        winningNumbers[0] = 0;
        winningNumbers[1] = 0;
        winningNumbers[2] = 0;
        winningNumbers[3] = 0;
        // 开奖阶段为否
        drawingPhase = false;
        // 发行索引+1
        issueIndex = issueIndex + 1;
        // 处理未中奖的奖金,投放到下期奖池
        uint256 amount;
        for (uint256 i = 0; i < 3; i++) {
            // 如果上期选中(4-i)个号码的人数为0
            if (getMatchingRewardAmount(issueIndex - 1, 4 - i) == 0) {
                // 数额 = 最后一次总奖金 * 奖金分配比例 / 100
                amount = amount.add(getTotalRewards(issueIndex - 1).mul(allocation[i]).div(100));
            }
        }
        if (amount > 0) {
            // 内部购买(买一张0,0,0,0的彩票,目的为了把奖金放到下期奖池)
            _internalBuy(amount, nullTicket);
        }
        emit Reset(issueIndex);
    }

    /**
     * @dev 进入开奖阶段,在开奖前必须先进入开奖阶段
     */
    function enterDrawingPhase() external onlyAdmin {
        // 确认不在开奖后
        require(!drawed(), "drawed");
        // 开奖阶段开始
        drawingPhase = true;
    }

    /**
     * @dev 私有获取中奖号码
     * @param _input 输入值
     */
    function _getNumber(bytes memory _input) private view returns (uint8) {
        // 结构hash
        bytes32 _structHash;
        // 随机数
        uint256 _randomNumber;
        // 最大数字
        uint8 _maxNumber = maxNumber;
        // 结构hash = hash(输入值)
        _structHash = keccak256(_input);
        // 随机数 = 将结果hash转为数字
        _randomNumber = uint256(_structHash);
        // 内联汇编
        assembly {
            // 随机数 = 随机数 % 最大数字 + 1
            _randomNumber := add(mod(_randomNumber, _maxNumber), 1)
        }
        // 中奖号码1 = 随机数 转为uint8
        return uint8(_randomNumber);
    }

    /**
     * @dev 开奖
     * @param _externalRandomNumber 外部随机数
     * @notice 添加外部随机数以防止节点验证程序利用
     */
    function drawing(uint256 _externalRandomNumber) external onlyAdmin {
        // 确认不在开奖后
        require(!drawed(), "reset?");
        // 确认处在开奖阶段
        require(drawingPhase, "enter drawing phase first");
        // 前一个区块的区块hash
        bytes32 _blockhash = blockhash(block.number - 1);

        // 在这里浪费一些汽油费
        for (uint256 i = 0; i < 10; i++) {
            // 获取总奖金
            getTotalRewards(issueIndex);
        }
        // 剩余的gas
        uint256 _gasleft = gasleft();

        // 中奖号码 1 (前一个区块的区块hash, 总地址数, 剩余gas, 外部随机数)
        winningNumbers[0] = _getNumber(abi.encode(_blockhash, totalAddresses, _gasleft, _externalRandomNumber));

        // 中奖号码 2 (前一个区块的区块hash, 获奖总数量, 剩余gas, 外部随机数)
        winningNumbers[1] = _getNumber(abi.encode(_blockhash, totalAmount, _gasleft, _externalRandomNumber));

        // 中奖号码 3 (前一个区块的区块hash, 最后时间戳, 剩余gas, 外部随机数)
        winningNumbers[2] = _getNumber(abi.encode(_blockhash, lastTimestamp, _gasleft, _externalRandomNumber));

        // 中奖号码 4 (前一个区块的区块hash, 剩余gas, 外部随机数)
        winningNumbers[3] = _getNumber(abi.encode(_blockhash, _gasleft, _externalRandomNumber));

        // 历史中奖号码[发行索引] = 中奖号码
        historyNumbers[issueIndex] = winningNumbers;
        // 历史奖金[发行索引] = 计算匹配的奖金数额
        historyAmount[issueIndex] = calculateMatchingRewardAmount();
        // 开奖阶段为否
        drawingPhase = false;
        // 触发事件
        emit Drawing(issueIndex, winningNumbers);
    }

    /**
     * @dev 内部购买
     * @param _price 价格
     * @param _numbers 号码数组
     */
    function _internalBuy(uint256 _price, uint8[4] memory _numbers) internal {
        // 确认不在开奖后
        require(!drawed(), "drawed, can not buy now");
        // 循环4个号码
        for (uint256 i = 0; i < 4; i++) {
            // 确认号码小于等于最大数
            require(_numbers[i] <= maxNumber, "exceed the maximum");
        }
        // NFT Token ID = 创建乐透NFT
        uint256 tokenId = lotteryNFT.newLotteryItem(address(this), _numbers, _price, issueIndex);
        // 发行索引=>TokenID数组推入新TokenID
        lotteryInfo[issueIndex].push(tokenId);
        // 获奖总数量+价格
        totalAmount = totalAmount.add(_price);
        // 最后时间戳=当前时间戳
        lastTimestamp = block.timestamp;
        // 触发事件
        emit Buy(address(this), tokenId);
    }

    /**
     * @dev 私有购买
     * @param _price 价格
     * @param _numbers 号码数组
     */
    function _buy(uint256 _price, uint8[4] memory _numbers) private returns (uint256) {
        // 循环4个号码
        for (uint256 i = 0; i < 4; i++) {
            // 确认号码小于等于最大数
            require(_numbers[i] <= maxNumber, "exceed number scope");
        }
        // NFT Token ID = 创建乐透NFT
        uint256 tokenId = lotteryNFT.newLotteryItem(msg.sender, _numbers, _price, issueIndex);
        // 发行索引=>TokenID数组推入新TokenID
        lotteryInfo[issueIndex].push(tokenId);
        // 如果用户信息长度=0
        if (userInfo[msg.sender].length == 0) {
            // 总地址数+1
            totalAddresses = totalAddresses + 1;
        }
        // 用户信息数组推入新TokenID
        userInfo[msg.sender].push(tokenId);
        // 总金额+价格
        totalAmount = totalAmount.add(_price);
        // 最后时间戳=当前时间戳
        lastTimestamp = block.timestamp;
        // 计算用户号码索引
        uint64[keyLengthForEachBuy] memory userNumberIndex = generateNumberIndexKey(_numbers);
        // 循环11位索引长度
        for (uint256 i = 0; i < keyLengthForEachBuy; i++) {
            // 用户购买总数额[发行索引][用户号码索引[i]] + 价格
            userBuyAmountSum[issueIndex][userNumberIndex[i]] = userBuyAmountSum[issueIndex][userNumberIndex[i]].add(_price);
        }
        return tokenId;
    }

    /**
     * @dev 检查器,是否可以购买
     */
    modifier canBuy(uint256 _price) {
        // 确认不在开奖后
        require(!drawed(), "drawed, can not buy now");
        // 确认不在开奖阶段
        require(!drawingPhase, "drawing, can not buy now");
        // 确认价格大于最小价格
        require(_price >= minPrice, "price must above minPrice");
        _;
    }

    /**
     * @dev 购买
     * @param _price 价格
     * @param _numbers 号码数组
     */
    function buy(uint256 _price, uint8[4] memory _numbers) external canBuy(_price) {
        // 私有购买
        uint256 tokenId = _buy(_price, _numbers);
        // 将token发送到当前合约
        IERC20(token).safeTransferFrom(address(msg.sender), address(this), _price);
        // 触发事件
        emit Buy(msg.sender, tokenId);
    }

    /**
     * @dev 批量购买
     * @param _price 价格
     * @param _numbers 号码数组
     */
    function multiBuy(uint256 _price, uint8[4][] memory _numbers) external canBuy(_price) {
        // 总价格
        uint256 totalPrice = 0;
        // 循环号码数组
        for (uint256 i = 0; i < _numbers.length; i++) {
            // 私有购买
            _buy(_price, _numbers[i]);
            totalPrice = totalPrice.add(_price);
        }
        // 将token发送到当前合约
        IERC20(token).safeTransferFrom(address(msg.sender), address(this), totalPrice);
        // 触发事件
        emit MultiBuy(msg.sender, totalPrice);
    }

    /**
     * @dev 领取奖励
     * @param _tokenId NFT Token ID
     */
    function claimReward(uint256 _tokenId) external {
        // 确认调用者为NFT拥有者
        require(msg.sender == lotteryNFT.ownerOf(_tokenId), "not from owner");
        // 确认NFT领取状态
        require(!lotteryNFT.getClaimStatus(_tokenId), "claimed");
        // 获取奖金数量
        uint256 reward = getRewardView(_tokenId);
        // 领取奖金
        lotteryNFT.claimReward(_tokenId);
        // 如果奖金>0
        if (reward > 0) {
            // 将奖金发送给用户
            IERC20(token).safeTransfer(address(msg.sender), reward);
        }
        // 触发事件
        emit Claim(msg.sender, _tokenId, reward);
    }

    /**
     * @dev 批量领取
     * @param _tickets NFT Token ID数组
     */
    function multiClaim(uint256[] memory _tickets) external {
        // 总奖金
        uint256 totalReward = 0;
        // 循环NFT Token ID数组
        for (uint256 i = 0; i < _tickets.length; i++) {
            // 确认调用者为NFT拥有者
            require(msg.sender == lotteryNFT.ownerOf(_tickets[i]), "not from owner");
            // 确认NFT领取状态
            require(!lotteryNFT.getClaimStatus(_tickets[i]), "claimed");
            // 获取奖金数量
            uint256 reward = getRewardView(_tickets[i]);
            // 如果奖金>0
            if (reward > 0) {
                // 总奖金累计
                totalReward = reward.add(totalReward);
            }
        }
        // 批量领取奖金
        lotteryNFT.multiClaimReward(_tickets);
        // 如果总奖金>0
        if (totalReward > 0) {
            // 将奖金发送给用户
            IERC20(token).safeTransfer(address(msg.sender), totalReward);
        }
        // 触发事件
        emit MultiClaim(msg.sender, totalReward);
    }

    /**
     * @dev 计算号码索引
     * @notice 4个中奖号码有11种中奖组合
     */
    function generateNumberIndexKey(uint8[4] memory number) public pure returns (uint64[keyLengthForEachBuy] memory) {
        // 将中奖号码赋值到临时变量
        uint64[4] memory tempNumber;
        tempNumber[0] = uint64(number[0]);
        tempNumber[1] = uint64(number[1]);
        tempNumber[2] = uint64(number[2]);
        tempNumber[3] = uint64(number[3]);
        // 按照固定的11位索引长度生成数组
        uint64[keyLengthForEachBuy] memory result;
        /*
         * 11种中奖组合,每一种组合中将每一个号码放大后组合成索引值
         * 0,1,2,3 = ([0] * 256^6) + (1 * 256^5 + [1] * 256^4) + (2 * 256^3 + [2] * 256^2) + (3 * 256 + [3])
         * 0,1,2 = ([0] * 256^4) + (1 * 256^3 + [1] * 256^2) + (2 * 256 + [2])
         * 0,1,3 = ([0] * 256^4) + (1 * 256^3 + [1] * 256^2) + (3 * 256 + [3])
         * 0,2,3 = ([0] * 256^4) + (2 * 256^3 + [2] * 256^2) + (3 * 256 + [3])
         * 1,2,3 = (1 * 256^5 + [1] * 256^4) + (2 * 256^3 + [2] * 256^2) + (3 * 256 + [3])
         * 0,1 = ([0] * 256^2) + (1 * 256 + [1])
         * 0,2 = ([0] * 256^2) + (2 * 256 + [2])
         * 0,3 = ([0] * 256^2) + (3 * 256 + [3])
         * 1,2 = (1 * 256^3 + [1] * 256^2) + (2 * 256 + [2])
         * 1,3 = (1 * 256^3 + [1] * 256^2) + (3 * 256 + [3])
         * 2,3 = (2 * 256^3 + [2] * 256^2) + (3 * 256 + [3])
         */
        result[0] =
            tempNumber[0] *
            256 *
            256 *
            256 *
            256 *
            256 *
            256 +
            1 *
            256 *
            256 *
            256 *
            256 *
            256 +
            tempNumber[1] *
            256 *
            256 *
            256 *
            256 +
            2 *
            256 *
            256 *
            256 +
            tempNumber[2] *
            256 *
            256 +
            3 *
            256 +
            tempNumber[3];

        result[1] = tempNumber[0] * 256 * 256 * 256 * 256 + 1 * 256 * 256 * 256 + tempNumber[1] * 256 * 256 + 2 * 256 + tempNumber[2];
        result[2] = tempNumber[0] * 256 * 256 * 256 * 256 + 1 * 256 * 256 * 256 + tempNumber[1] * 256 * 256 + 3 * 256 + tempNumber[3];
        result[3] = tempNumber[0] * 256 * 256 * 256 * 256 + 2 * 256 * 256 * 256 + tempNumber[2] * 256 * 256 + 3 * 256 + tempNumber[3];
        result[4] =
            1 *
            256 *
            256 *
            256 *
            256 *
            256 +
            tempNumber[1] *
            256 *
            256 *
            256 *
            256 +
            2 *
            256 *
            256 *
            256 +
            tempNumber[2] *
            256 *
            256 +
            3 *
            256 +
            tempNumber[3];

        result[5] = tempNumber[0] * 256 * 256 + 1 * 256 + tempNumber[1];
        result[6] = tempNumber[0] * 256 * 256 + 2 * 256 + tempNumber[2];
        result[7] = tempNumber[0] * 256 * 256 + 3 * 256 + tempNumber[3];
        result[8] = 1 * 256 * 256 * 256 + tempNumber[1] * 256 * 256 + 2 * 256 + tempNumber[2];
        result[9] = 1 * 256 * 256 * 256 + tempNumber[1] * 256 * 256 + 3 * 256 + tempNumber[3];
        result[10] = 2 * 256 * 256 * 256 + tempNumber[2] * 256 * 256 + 3 * 256 + tempNumber[3];

        return result;
    }

    /**
     * @dev 计算匹配的中奖数量
     * @return [总奖池数额,一等奖数量,二等奖数量, 三等奖数量]
     */
    function calculateMatchingRewardAmount() internal view returns (uint256[4] memory) {
        // 按照固定的11位索引长度生成数组,并获取当前中奖号码对应的11位索引
        uint64[keyLengthForEachBuy] memory numberIndexKey = generateNumberIndexKey(winningNumbers);

        // 一等奖 = 用户购买总数额[发行索引][索引0] (索引0完全匹配了4个号码组合)
        uint256 totalAmout1 = userBuyAmountSum[issueIndex][numberIndexKey[0]];

        // 二等奖总和 = 用户购买总数额[发行索引][索引1~4] (索引1~4匹配了3个号码的组合)
        uint256 sumForTotalAmout2 = userBuyAmountSum[issueIndex][numberIndexKey[1]];
        sumForTotalAmout2 = sumForTotalAmout2.add(userBuyAmountSum[issueIndex][numberIndexKey[2]]);
        sumForTotalAmout2 = sumForTotalAmout2.add(userBuyAmountSum[issueIndex][numberIndexKey[3]]);
        sumForTotalAmout2 = sumForTotalAmout2.add(userBuyAmountSum[issueIndex][numberIndexKey[4]]);

        // 二等奖 = 二等奖总和 - 一等奖 * 4 (二等奖中奖者里包含了一等奖中奖者,所以要减去4倍一等奖)
        uint256 totalAmout2 = sumForTotalAmout2.sub(totalAmout1.mul(4));

        // 三等奖总和 = 用户购买总数额[发行索引][索引5~10] (索引5~10匹配了2个号码的组合)
        uint256 sumForTotalAmout3 = userBuyAmountSum[issueIndex][numberIndexKey[5]];
        sumForTotalAmout3 = sumForTotalAmout3.add(userBuyAmountSum[issueIndex][numberIndexKey[6]]);
        sumForTotalAmout3 = sumForTotalAmout3.add(userBuyAmountSum[issueIndex][numberIndexKey[7]]);
        sumForTotalAmout3 = sumForTotalAmout3.add(userBuyAmountSum[issueIndex][numberIndexKey[8]]);
        sumForTotalAmout3 = sumForTotalAmout3.add(userBuyAmountSum[issueIndex][numberIndexKey[9]]);
        sumForTotalAmout3 = sumForTotalAmout3.add(userBuyAmountSum[issueIndex][numberIndexKey[10]]);

        // 三等奖 = 三等奖总和 + 一等奖 * 6 - 二等奖总和 * 3
        // (三等奖中包含了3种二等奖组合,6种一等奖组合,二等奖总和的3倍中包含12个一等奖,所以三等奖减去了3个二等奖还要加回来6个一等奖
        uint256 totalAmout3 = sumForTotalAmout3.add(totalAmout1.mul(6)).sub(sumForTotalAmout2.mul(3));
        // 返回[总奖池数额, 一等奖数量, 二等奖数量, 三等奖数量]
        return [totalAmount, totalAmout1, totalAmout2, totalAmout3];
    }

    /**
     * @dev 获取匹配的奖金数额
     * @param _issueIndex 发行索引
     * @param _matchingNumber 匹配几个号码,范围[2,3,4],如果值为5,返回的是总奖池数额
     */
    function getMatchingRewardAmount(uint256 _issueIndex, uint256 _matchingNumber) public view returns (uint256) {
        return historyAmount[_issueIndex][5 - _matchingNumber];
    }

    /**
     * @dev 返回历史奖池总数量
     * @param _issueIndex 发行索引
     */
    function getTotalRewards(uint256 _issueIndex) public view returns (uint256) {
        // 确认发行索引小于当前索引
        require(_issueIndex <= issueIndex, "_issueIndex <= issueIndex");

        // 如果不是开奖后状态,并且发行索引为当前索引
        if (!drawed() && _issueIndex == issueIndex) {
            // 返回总奖池数额
            return totalAmount;
        }
        // 返回历史中奖数量[发行索引][0]
        return historyAmount[_issueIndex][0];
    }

    /**
     * @dev 返回获奖金额
     * @param _tokenId NFT Token ID
     * @notice 奖金计算公式: 购买的出价price / 奖池数量 * 奖池奖金
     */
    function getRewardView(uint256 _tokenId) public view returns (uint256) {
        // 通过TokenID获取发行索引
        uint256 _issueIndex = lotteryNFT.getLotteryIssueIndex(_tokenId);
        // 通过TokenID获取用户购买的号码
        uint8[4] memory lotteryNumbers = lotteryNFT.getLotteryNumbers(_tokenId);
        // 通过TokenID获取中奖号码
        uint8[4] memory _winningNumbers = historyNumbers[_issueIndex];
        // 确认奖池数量不为0
        require(_winningNumbers[0] != 0, "not drawed");

        // 匹配的号码
        uint256 matchingNumber = 0;
        // 循环号码
        for (uint256 i = 0; i < lotteryNumbers.length; i++) {
            // 如果中奖号码[i] = 用户购买的号码[i]
            if (_winningNumbers[i] == lotteryNumbers[i]) {
                // 匹配的号码 + 1
                matchingNumber = matchingNumber + 1;
            }
        }
        // 奖金
        uint256 reward = 0;
        // 如果匹配的号码>1
        if (matchingNumber > 1) {
            // 数量 = 购买彩票时的单价price
            uint256 amount = lotteryNFT.getLotteryAmount(_tokenId);
            // 奖池分配数额 = 历史奖池总数量(发行索引) * 分配额[4 - 匹配数量] / 100 (根据当期总奖池数量和匹配的号码数量计算对应的奖池比例)
            uint256 poolAmount = getTotalRewards(_issueIndex).mul(allocation[4 - matchingNumber]).div(100);
            // 奖金 = 数量 * 1e12 / 奖池数量(根据发行索引和匹配号码数量获取到的对应奖池大小) * 奖池分配数额
            reward = amount.mul(1e12).div(getMatchingRewardAmount(_issueIndex, matchingNumber)).mul(poolAmount);
        }
        // 返回奖金 / 1e12
        return reward.div(1e12);
    }

    /**
     * @dev 通过之前的开发者更新管理员地址
     * @param _adminAddress 管理员地址
     */
    function setAdmin(address _adminAddress) public onlyOwner {
        adminAddress = _adminAddress;
    }

    /**
     * @dev 退出时不关心奖励。仅紧急情况
     * @param _amount 数额
     */
    function adminWithdraw(uint256 _amount) public onlyOwner {
        IERC20(token).safeTransfer(address(msg.sender), _amount);
        emit DevWithdraw(msg.sender, _amount);
    }

    /**
     * @dev 设置一张票的最低价格
     * @param _price 价格
     */
    function setMinPrice(uint256 _price) external onlyOwner {
        minPrice = _price;
    }

    /**
     * @dev 设置最大号码
     * @param _maxNumber 最大号码
     */
    function setMaxNumber(uint8 _maxNumber) external onlyOwner {
        maxNumber = _maxNumber;
    }

    /**
     * @dev 设置奖池分配比例
     * @param _allcation1 分配比例1 50%
     * @param _allcation2 分配比例2 20%
     * @param _allcation3 分配比例3 10%
     */
    function setAllocation(
        uint8 _allcation1,
        uint8 _allcation2,
        uint8 _allcation3
    ) external onlyOwner {
        allocation = [_allcation1, _allcation2, _allcation3];
    }
}
