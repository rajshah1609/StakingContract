// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.17;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";

library SafeMath {
    /**
     * @dev Multiplies two numbers, throws on overflow.
     */
    function mul(uint256 _a, uint256 _b) internal pure returns (uint256 c) {
        // Gas optimization: this is cheaper than asserting 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-solidity/pull/522
        if (_a == 0) {
            return 0;
        }

        c = _a * _b;
        assert(c / _a == _b);
        return c;
    }

    /**
     * @dev Integer division of two numbers, truncating the quotient.
     */
    function div(uint256 _a, uint256 _b) internal pure returns (uint256) {
        // assert(_b > 0); // Solidity automatically throws when dividing by 0
        // uint256 c = _a / _b;
        // assert(_a == _b * c + _a % _b); // There is no case in which this doesn't hold
        return _a / _b;
    }

    /**
     * @dev Subtracts two numbers, throws on overflow (i.e. if subtrahend is greater than minuend).
     */
    function sub(uint256 _a, uint256 _b) internal pure returns (uint256) {
        assert(_b <= _a);
        return _a - _b;
    }

    /**
     * @dev Adds two numbers, throws on overflow.
     */
    function add(uint256 _a, uint256 _b) internal pure returns (uint256 c) {
        c = _a + _b;
        assert(c >= _a);
        return c;
    }
}

library AddressUtils {
    /**
     * Returns whether the target address is a contract
     * @dev This function will return false if invoked during the constructor of a contract,
     * as the code is not actually created until after the constructor finishes.
     * @param _addr address to check
     * @return whether the target address is a contract
     */
    function isContract(address _addr) internal view returns (bool) {
        uint256 size;
        // XXX Currently there is no better way to check if there is a contract in an address
        // than to check the size of the code at that address.
        // See https://ethereum.stackexchange.com/a/14016/36603
        // for more details about how this works.
        // TODO Check this again before the Serenity release, because all addresses will be
        // contracts then.
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            size := extcodesize(_addr)
        }
        return size > 0;
    }
}

contract StakeFXD is Context, Pausable, Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using AddressUtils for address;

    uint256 private ONE_DAY = 60; //86400

    IERC20 token;
    uint256 public totalStaked;
    uint256 public minStakeAmount = 100 * 10 ** 18;
    uint256 public maxStakeAmount = 1000 * 10 ** 18;
    uint256 public coolOff = ONE_DAY * 7;
    uint256 public interest;
    uint256 public totalRedeemed = 0;
    uint256 public redeemInterval = 10 * ONE_DAY;
    uint256 public startTime;
    uint256 public maxStakingDays;
    uint256 public expiryTime;
    uint256 public maxPoolAmount = 10000 * 10 ** 18; //greater than or equal to maxstakeamount
    uint256 public pendingPoolAmount = maxPoolAmount;

    uint256 public interestPrecision = 100;

    event Staked(address staker, uint256 amount);

    event Unstaked(address staker, uint256 amount);
    event WithdrewStake(address staker, uint256 principal, uint256 earnings);
    event ClaimedRewards(address staker, uint256 amount);

    // Parameter Change Events
    event MinStakeAmountChanged(uint256 prevValue, uint256 newValue);
    event MaxStakeAmountChanged(uint256 prevValue, uint256 newValue);
    event RateChanged(uint256 prevValue, uint256 newValue);
    event CoolOffChanged(uint256 prevValue, uint256 newValue);
    event RedeemIntervalChanged(uint256 prevValue, uint256 newValue);
    event InterestPrecisionChanged(uint256 prevValue, uint256 newValue);
    event StartTimeChanged(uint256 prevValue, uint256 newValue);
    event MaxStakingDaysChanged(uint256 prevValue, uint256 newValue);
    event ExpiryTimeChanged(uint256 prevValue, uint256 newValue);
    event MaxPoolAmountChanged(uint256 prevValue, uint256 newValue);

    event WithdrewTokens(address beneficiary, uint256 amount);
    event WithdrewXdc(address beneficiary, uint256 amount);

    struct Stake {
        address stakerHolder;
        uint256 stakedAmount;
        bool staked;
        bool exists;
        bool unstaked;
        uint256 stakedTime;
        uint256 unstakedTime;
        uint256 totalRedeemed;
        uint256 lastRedeemedAt;
        uint256 balance;
        uint256 originalStakeAmount;
    }

    mapping(address => Stake) public stakes;
    mapping(address => bool) public addressStaked;
    address[] public stakeHolders;

    modifier whenStaked() {
        require(stakes[msg.sender].staked == true, "FXD: not staked");
        _;
    }

    modifier whenNotStaked() {
        require(stakes[msg.sender].staked == false, "FXD: already staked");
        _;
    }

    modifier whenNotUnStaked() {
        require(stakes[msg.sender].unstaked == false, "FXD: in unstake period");
        _;
    }

    modifier whenUnStaked() {
        require(stakes[msg.sender].unstaked == true, "FXD: not un-staked");
        _;
    }

    modifier canRedeemDrip(address staker) {
        require(stakes[staker].exists, "FXD: staker does not exist");
        require(
            stakes[staker].lastRedeemedAt + redeemInterval <= block.timestamp,
            "FXD: cannot claim drip yet"
        );
        _;
    }

    function canWithdrawStake(address staker) public view returns (bool) {
        require(stakes[staker].exists, "FXD: stakeholder does not exists");
        require(
            stakes[staker].staked == false,
            "FXD: stakeholder still has stake"
        );
        require(stakes[staker].unstaked == true, "FXD: not in unstake period");
        uint256 unstakeTenure = block.timestamp - stakes[staker].unstakedTime;
        return coolOff < unstakeTenure;
    }

    constructor(IERC20 token_, uint256 interest_) {
        require(
            address(token_) != address(0),
            "Token Address cannot be address 0"
        );
        token = token_;
        interest = interest_;
    }

    function transferToken(address to, uint256 amount) external onlyOwner {
        require(token.transfer(to, amount), "Token transfer failed!");
    }

    function stake(uint256 amount_) public whenNotStaked whenNotUnStaked {
        require(
            totalStaked + amount_ <= maxPoolAmount,
            "Exceeds maximum pool value"
        );
        require(amount_ >= minStakeAmount, "FXD: invalid amount");
        require(amount_ <= maxStakeAmount, "FXD: invalid amount");

        Stake memory staker = stakes[msg.sender];

        staker.staked = true;
        if (staker.exists == false) {
            staker.exists = true;
            staker.stakerHolder = msg.sender;
        }

        stakeHolders.push(msg.sender);
        staker.stakedTime = block.timestamp;
        staker.totalRedeemed = 0;
        if (startTime > 0) staker.lastRedeemedAt = startTime;
        else staker.lastRedeemedAt = block.timestamp;
        staker.stakedAmount = amount_;
        staker.originalStakeAmount = amount_;
        staker.balance = 0;
        stakes[msg.sender] = staker;

        totalStaked = totalStaked.add(amount_);
        pendingPoolAmount = pendingPoolAmount.sub(amount_);

        token.safeTransferFrom(msg.sender, address(this), amount_);

        emit Staked(msg.sender, amount_);
    }

    function unstake() public whenStaked whenNotUnStaked {
        uint256 leftoverBalance = _earned(msg.sender);
        Stake memory staker = stakes[msg.sender];
        staker.unstakedTime = block.timestamp;
        staker.staked = false;
        staker.balance = leftoverBalance;
        staker.unstaked = true;
        stakes[msg.sender] = staker;

        totalStaked = totalStaked.sub(staker.stakedAmount);
        totalStaked = pendingPoolAmount.add(staker.stakedAmount);
        (bool exists, uint256 stakerIndex) = getStakerIndex(msg.sender);
        require(exists, "FXD: staker does not exist");
        stakeHolders[stakerIndex] = stakeHolders[stakeHolders.length - 1];
        delete stakeHolders[stakeHolders.length - 1];
        stakeHolders.pop();

        emit Unstaked(msg.sender, staker.stakedAmount);
    }

    function _earned(
        address beneficiary_
    ) internal view returns (uint256 earned) {
        if (stakes[beneficiary_].staked == false) return 0;
        uint256 tenure;
        if (block.timestamp > expiryTime)
            tenure = (expiryTime - stakes[beneficiary_].lastRedeemedAt);
        else tenure = (block.timestamp - stakes[beneficiary_].lastRedeemedAt);
        earned = tenure
            .div(ONE_DAY)
            .mul(stakes[beneficiary_].stakedAmount)
            .mul(interest.div(interestPrecision))
            .div(100)
            .div(365);
    }

    function claimEarned() public canRedeemDrip(_msgSender()) returns (bool) {
        require(stakes[_msgSender()].staked == true, "FXD: not staked");

        // update the redeemdate even if earnings are 0
        uint256 earnings = _earned(_msgSender());

        if (earnings > 0) {
            token.transfer(_msgSender(), earnings);
        }

        stakes[_msgSender()].totalRedeemed += earnings;
        stakes[_msgSender()].lastRedeemedAt = block.timestamp;

        totalRedeemed += earnings;

        emit ClaimedRewards(_msgSender(), earnings);
    }

    function withdrawStake() public whenUnStaked {
        require(canWithdrawStake(msg.sender), "FXD: cannot withdraw yet");
        Stake memory staker = stakes[msg.sender];
        uint256 withdrawAmount = staker.stakedAmount;
        uint256 leftoverBalance = staker.balance;
        token.transfer(msg.sender, withdrawAmount);
        if (leftoverBalance > 0) token.transfer(msg.sender, leftoverBalance);
        staker.stakedAmount = 0;
        staker.balance = 0;
        staker.unstaked = false;
        staker.totalRedeemed += leftoverBalance;
        staker.lastRedeemedAt = block.timestamp;
        stakes[msg.sender] = staker;
        totalRedeemed += leftoverBalance;
        emit WithdrewStake(msg.sender, withdrawAmount, leftoverBalance);
    }

    function nextDripAt(address claimerAddress) public view returns (uint256) {
        require(
            stakes[claimerAddress].staked == true,
            "FXD: address has not staked"
        );
        return stakes[claimerAddress].lastRedeemedAt + redeemInterval;
    }

    function canWithdrawStakeIn(address staker) public view returns (uint256) {
        require(stakes[staker].exists, "FXD: stakeholder does not exists");
        require(
            stakes[staker].staked == false,
            "FXD: stakeholder still has stake"
        );
        uint256 unstakeTenure = block.timestamp - stakes[staker].unstakedTime;
        if (coolOff < unstakeTenure) return 0;
        return coolOff - unstakeTenure;
    }

    function getAllStakeHolder() public view returns (address[] memory) {
        return stakeHolders;
    }

    function getStakerIndex(
        address staker
    ) public view returns (bool, uint256) {
        for (uint256 i = 0; i < stakeHolders.length; i++) {
            if (stakeHolders[i] == staker) return (true, i);
        }
        return (false, 0);
    }

    function earned(address staker) public view returns (uint256 earnings) {
        earnings = _earned(staker);
    }

    function getNumberOfStakers() public view returns (uint256 numberofStaker) {
        return stakeHolders.length;
    }

    /*
        Owner Functionality Starts
    */

    function setMinStakeAmount(uint256 minStakeAmount_) public onlyOwner {
        require(
            minStakeAmount_ > 0,
            "FXD: minimum stake amount should be greater than 0"
        );
        uint256 prevValue = minStakeAmount;
        minStakeAmount = minStakeAmount_;
        emit MinStakeAmountChanged(prevValue, minStakeAmount);
    }

    function setMaxStakeAmount(uint256 maxStakeAmount_) public onlyOwner {
        require(
            maxStakeAmount_ > 0,
            "FXD: maximum stake amount should be greater than 0"
        );
        uint256 prevValue = maxStakeAmount;
        maxStakeAmount = maxStakeAmount_;
        emit MaxStakeAmountChanged(prevValue, maxStakeAmount);
    }

    function setRate(uint256 interest_) public onlyOwner {
        uint256 prevValue = interest;
        interest = interest_;
        emit RateChanged(prevValue, interest);
    }

    function setCoolOff(uint256 coolOff_) public onlyOwner {
        uint256 prevValue = coolOff;
        coolOff = coolOff_;
        emit CoolOffChanged(prevValue, coolOff);
    }

    function setRedeemInterval(uint256 redeemInterval_) public onlyOwner {
        uint256 prevValue = redeemInterval;
        redeemInterval = redeemInterval_;
        emit RedeemIntervalChanged(prevValue, redeemInterval);
    }

    function setInterestPrecision(uint256 interestPrecision_) public onlyOwner {
        require(interestPrecision_ > 0, "FXD: precision cannot be 0");
        uint256 prevValue = interestPrecision;
        interestPrecision = interestPrecision_;
        emit InterestPrecisionChanged(prevValue, interestPrecision);
    }

    function setStartTime(uint256 startTime_) public onlyOwner {
        require(
            maxStakingDays > 0,
            "FXD: please set max staking days to be greater than 0"
        );
        require(startTime_ > 0, "FXD: startTime cannot be 0");
        require(
            block.timestamp < startTime_,
            "FXD: startTime must be in the future"
        );
        uint256 prevValue = startTime;
        startTime = startTime_;
        emit StartTimeChanged(prevValue, startTime);
        prevValue = expiryTime;
        expiryTime = startTime + (maxStakingDays * ONE_DAY);
        emit ExpiryTimeChanged(prevValue, expiryTime);
        for (uint256 i = 0; i < stakeHolders.length; i++) {
            stakes[stakeHolders[i]].lastRedeemedAt = startTime;
        }
    }

    function setMaxStakingDays(uint256 maxStakingDays_) public onlyOwner {
        require(maxStakingDays_ > 0, "FXD: maxStakingDays cannot be 0");
        uint256 prevValue = maxStakingDays;
        maxStakingDays = maxStakingDays_;
        emit StartTimeChanged(prevValue, maxStakingDays);
    }

    function setMaxPoolAmount(uint256 maxPoolAmount_) public onlyOwner {
        require(maxPoolAmount_ > 0, "FXD: maxPoolAmount cannot be 0");
        require(
            maxPoolAmount_ >= minStakeAmount,
            "FXD: maxPoolAmount should be greater than minStakeAmount"
        );
        require(
            maxPoolAmount_ >= maxStakeAmount,
            "FXD: maxPoolAmount should be greater than maxStakeAmount"
        );
        uint256 prevValue = maxPoolAmount;
        maxPoolAmount = maxPoolAmount_;
        if (maxPoolAmount > prevValue)
            pendingPoolAmount = pendingPoolAmount.add(
                maxPoolAmount - prevValue
            );
        else
            pendingPoolAmount = pendingPoolAmount.add(
                prevValue - maxPoolAmount
            );
        emit MaxPoolAmountChanged(prevValue, maxPoolAmount);
    }

    function withdrawTokens(
        address beneficiary_,
        uint256 amount_
    ) public onlyOwner {
        require(amount_ > 0, "FXD: token amount has to be greater than 0");
        token.safeTransfer(beneficiary_, amount_);
        emit WithdrewTokens(beneficiary_, amount_);
    }

    function withdrawXdc(
        address beneficiary_,
        uint256 amount_
    ) public onlyOwner {
        require(amount_ > 0, "FXD: xdc amount has to be greater than 0");
        payable(beneficiary_).transfer(amount_);
        emit WithdrewXdc(beneficiary_, amount_);
    }

    function destroy() public onlyOwner {
        selfdestruct(payable(owner()));
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
