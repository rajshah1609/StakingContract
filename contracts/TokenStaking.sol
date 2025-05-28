// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract TokenStaking is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 private constant ONE_DAY = 86400;

    // Immutable state variables (set in constructor)
    IERC20 public immutable stakingToken;
    uint256 public immutable tokenDecimals;
    string public tokenSymbol;
    string public poolName;
    bool public paused;

    // Configurable state variables (set in initialize)
    uint256 public totalStaked;
    uint256 public minStakeAmount;
    uint256 public maxStakeAmount;
    uint256 public coolOff;
    uint256 public interest;
    uint256 public totalRedeemed;
    uint256 public redeemInterval;
    uint256 public maxPoolAmount;
    uint256 public pendingPoolAmount;
    uint256 public interestPrecision;
    uint256 public startTime;
    uint256 public maxStakingDays;
    uint256 public expiryTime;

    // Initialization flag
    bool private initialized;

    struct Stake {
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
    address[] public stakeHolders;

    // Events
    event Initialized(
        uint256 minStakeAmount,
        uint256 maxStakeAmount,
        uint256 coolOff,
        uint256 redeemInterval,
        uint256 maxPoolAmount,
        uint256 interestPrecision
    );
    event Staked(address indexed staker, uint256 amount);
    event Unstaked(address indexed staker, uint256 amount);
    event WithdrewStake(address indexed staker, uint256 principal, uint256 earnings);
    event ClaimedRewards(address indexed staker, uint256 amount);
    event Paused();
    event Unpaused();
    event MinStakeAmountChanged(uint256 prevValue, uint256 newValue);
    event MaxStakeAmountChanged(uint256 prevValue, uint256 newValue);
    event RateChanged(uint256 prevValue, uint256 newValue);
    event CoolOffChanged(uint256 prevValue, uint256 newValue);
    event RedeemIntervalChanged(uint256 prevValue, uint256 newValue);
    event StartTimeChanged(uint256 prevValue, uint256 newValue);
    event MaxStakingDaysChanged(uint256 prevValue, uint256 newValue);
    event ExpiryTimeChanged(uint256 prevValue, uint256 newValue);
    event MaxPoolAmountChanged(uint256 prevValue, uint256 newValue);
    event WithdrewTokens(address indexed beneficiary, uint256 amount);
    event InterestPrecisionChanged(uint256 prevValue, uint256 newValue);

    modifier whenInitialized() {
        require(initialized, "Not initialized");
        _;
    }

    modifier whenNotInitialized() {
        require(!initialized, "Already initialized");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Contract paused");
        _;
    }

    modifier whenStaked() {
        require(stakes[msg.sender].staked, "Not staked");
        _;
    }

    modifier whenNotStaked() {
        require(!stakes[msg.sender].staked, "Already staked");
        _;
    }

    modifier whenNotUnStaked() {
        require(!stakes[msg.sender].unstaked, "In unstake period");
        _;
    }

    modifier whenNotExpired() {
        require(block.timestamp < expiryTime, "Contract expired");
        _;
    }

    modifier canRedeemDrip(address staker) {
        require(stakes[staker].exists, "Staker does not exist");
        require(
            stakes[staker].lastRedeemedAt + redeemInterval <= block.timestamp,
            "Cannot claim drip yet"
        );
        _;
    }

    modifier whenUnStaked() {
        require(stakes[msg.sender].unstaked, "Not unstaked");
        _;
    }

    constructor(
        IERC20 token_,
        uint256 interest_,
        uint256 decimals_,
        string memory poolName_
    ) {
        require(address(token_) != address(0), "Zero address");
        require(bytes(poolName_).length > 0, "Empty name");
        
        stakingToken = token_;
        tokenDecimals = decimals_;
        poolName = poolName_;
        interest = interest_;
        
        // Try to get symbol from token
        try IERC20Metadata(address(token_)).symbol() returns (string memory symbol) {
            tokenSymbol = symbol;
        } catch {
            tokenSymbol = "UNKNOWN";
        }
    }

    function initialize(
        uint256 minStakeAmount_,
        uint256 maxStakeAmount_,
        uint256 coolOff_,
        uint256 redeemInterval_,
        uint256 maxPoolAmount_,
        uint256 interestPrecision_
    ) external onlyOwner whenNotInitialized {
        require(minStakeAmount_ > 0, "Min stake = 0");
        require(maxStakeAmount_ >= minStakeAmount_, "Max < min");
        require(maxPoolAmount_ >= maxStakeAmount_, "Pool < max");
        require(interestPrecision_ > 0, "Precision = 0");

        minStakeAmount = minStakeAmount_ * 10**tokenDecimals;
        maxStakeAmount = maxStakeAmount_ * 10**tokenDecimals;
        maxPoolAmount = maxPoolAmount_ * 10**tokenDecimals;
        coolOff = coolOff_;
        redeemInterval = redeemInterval_;
        interestPrecision = interestPrecision_;
        pendingPoolAmount = maxPoolAmount;
        
        initialized = true;

        emit Initialized(
            minStakeAmount,
            maxStakeAmount,
            coolOff,
            redeemInterval,
            maxPoolAmount,
            interestPrecision
        );
    }

    function stake(uint256 amount_) external whenInitialized whenNotStaked whenNotUnStaked whenNotExpired nonReentrant {
        require(totalStaked + amount_ <= maxPoolAmount, "Exceeds maximum pool value");
        require(amount_ >= minStakeAmount, "Invalid amount: below minimum");
        require(amount_ <= maxStakeAmount, "Invalid amount: above maximum");

        Stake memory staker = stakes[msg.sender];

        staker.staked = true;
        if (!staker.exists) {
            staker.exists = true;
            stakeHolders.push(msg.sender);
        }

        staker.stakedTime = block.timestamp;
        staker.totalRedeemed = 0;
        if (startTime > 0) {
            staker.lastRedeemedAt = startTime;
        } else {
            staker.lastRedeemedAt = block.timestamp;
        }
        staker.stakedAmount = amount_;
        staker.originalStakeAmount = amount_;
        staker.balance = 0;
        stakes[msg.sender] = staker;

        totalStaked += amount_;
        pendingPoolAmount -= amount_;

        stakingToken.safeTransferFrom(msg.sender, address(this), amount_);

        emit Staked(msg.sender, amount_);
    }

    function unstake() external whenStaked whenNotUnStaked nonReentrant {
        require(expiryTime <= block.timestamp, "Contract hasn't expired yet");
        uint256 leftoverBalance = _earned(msg.sender);
        Stake memory staker = stakes[msg.sender];
        staker.unstakedTime = block.timestamp;
        staker.staked = false;
        staker.balance = leftoverBalance;
        staker.unstaked = true;
        stakes[msg.sender] = staker;

        totalStaked -= staker.stakedAmount;
        pendingPoolAmount += staker.stakedAmount;

        (bool exists, uint256 stakerIndex) = getStakerIndex(msg.sender);
        require(exists, "Staker does not exist");
        stakeHolders[stakerIndex] = stakeHolders[stakeHolders.length - 1];
        stakeHolders.pop();

        emit Unstaked(msg.sender, staker.stakedAmount);
    }

    function _earned(address beneficiary_) internal view returns (uint256 earned) {
        if (stakes[beneficiary_].staked == false) return 0;
        
        uint256 tenure;
        if (block.timestamp > expiryTime) {
            tenure = (expiryTime - stakes[beneficiary_].lastRedeemedAt);
        } else {
            tenure = (block.timestamp - stakes[beneficiary_].lastRedeemedAt);
        }
        
        // Calculate earnings using standard arithmetic instead of SafeMath
        // Since Solidity 0.8.x has built-in overflow checks
        earned = tenure * stakes[beneficiary_].stakedAmount * interest;
        earned = earned / interestPrecision / 100 / (365 * ONE_DAY);
        
        return earned;
    }

    function claimEarned(address claimAddress) public canRedeemDrip(claimAddress) nonReentrant {
        require(stakes[claimAddress].staked == true, "Not staked");

        uint256 earnings = _earned(claimAddress);

        if (earnings > 0) {
            stakingToken.safeTransfer(claimAddress, earnings);
        }

        stakes[claimAddress].totalRedeemed += earnings;
        stakes[claimAddress].lastRedeemedAt = block.timestamp;
        totalRedeemed += earnings;

        emit ClaimedRewards(claimAddress, earnings);
    }

    function withdrawStake() public whenUnStaked {
        require(canWithdrawStake(msg.sender), "Cannot withdraw yet");
        Stake memory staker = stakes[msg.sender];
        uint256 withdrawAmount = staker.stakedAmount;
        uint256 leftoverBalance = staker.balance;

        stakingToken.safeTransfer(msg.sender, withdrawAmount);
        if (leftoverBalance > 0) {
            stakingToken.safeTransfer(msg.sender, leftoverBalance);
        }

        staker.stakedAmount = 0;
        staker.balance = 0;
        staker.unstaked = false;
        staker.totalRedeemed += leftoverBalance;
        staker.lastRedeemedAt = block.timestamp;
        stakes[msg.sender] = staker;
        totalRedeemed += leftoverBalance;

        emit WithdrewStake(msg.sender, withdrawAmount, leftoverBalance);
    }

    function canWithdrawStake(address staker) public view returns (bool) {
        require(stakes[staker].exists, "Stakeholder does not exist");
        require(stakes[staker].staked == false, "Stakeholder still has stake");
        require(stakes[staker].unstaked == true, "Not in unstake period");
        uint256 unstakeTenure = block.timestamp - stakes[staker].unstakedTime;
        return coolOff < unstakeTenure;
    }

    function earned(address staker) public view returns (uint256) {
        return _earned(staker);
    }

    function getStakerIndex(address staker) public view returns (bool, uint256) {
        for (uint256 i = 0; i < stakeHolders.length; i++) {
            if (stakeHolders[i] == staker) return (true, i);
        }
        return (false, 0);
    }

    function getAllStakeHolders() public view returns (address[] memory) {
        return stakeHolders;
    }

    function getNumberOfStakers() public view returns (uint256) {
        return stakeHolders.length;
    }

    // Owner functions
    function setMinStakeAmount(uint256 minStakeAmount_) external onlyOwner {
        require(minStakeAmount_ > 0, "Minimum stake amount should be greater than 0");
        uint256 prevValue = minStakeAmount;
        minStakeAmount = minStakeAmount_;
        emit MinStakeAmountChanged(prevValue, minStakeAmount);
    }

    function setMaxStakeAmount(uint256 maxStakeAmount_) external onlyOwner {
        require(maxStakeAmount_ > 0, "Maximum stake amount should be greater than 0");
        uint256 prevValue = maxStakeAmount;
        maxStakeAmount = maxStakeAmount_;
        emit MaxStakeAmountChanged(prevValue, maxStakeAmount);
    }

    function setRate(uint256 interest_) external onlyOwner {
        uint256 prevValue = interest;
        interest = interest_;
        emit RateChanged(prevValue, interest);
    }

    function setCoolOff(uint256 coolOff_) external onlyOwner {
        uint256 prevValue = coolOff;
        coolOff = coolOff_;
        emit CoolOffChanged(prevValue, coolOff);
    }

    function setRedeemInterval(uint256 redeemInterval_) external onlyOwner {
        uint256 prevValue = redeemInterval;
        redeemInterval = redeemInterval_;
        emit RedeemIntervalChanged(prevValue, redeemInterval);
    }

    function setStartTime(uint256 startTime_) external onlyOwner {
        require(maxStakingDays > 0, "Set max staking days first");
        require(startTime_ > 0, "Start time cannot be 0");
        require(block.timestamp < startTime_, "Start time must be in the future");
        
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

    function setMaxStakingDays(uint256 maxStakingDays_) external onlyOwner {
        require(maxStakingDays_ > 0, "Max staking days cannot be 0");
        uint256 prevValue = maxStakingDays;
        maxStakingDays = maxStakingDays_;
        emit MaxStakingDaysChanged(prevValue, maxStakingDays);
    }

    function setMaxPoolAmount(uint256 maxPoolAmount_) external onlyOwner {
        require(maxPoolAmount_ > 0, "Max pool amount cannot be 0");
        require(maxPoolAmount_ >= minStakeAmount, "Max pool amount should be greater than min stake amount");
        require(maxPoolAmount_ >= maxStakeAmount, "Max pool amount should be greater than max stake amount");
        
        uint256 prevValue = maxPoolAmount;
        maxPoolAmount = maxPoolAmount_;
        if (maxPoolAmount > prevValue) {
            pendingPoolAmount += (maxPoolAmount - prevValue);
        } else {
            pendingPoolAmount -= (prevValue - maxPoolAmount);
        }
        emit MaxPoolAmountChanged(prevValue, maxPoolAmount);
    }

    function withdrawTokens(address beneficiary_, uint256 amount_) external onlyOwner {
        require(amount_ > 0, "Amount has to be greater than 0");
        stakingToken.safeTransfer(beneficiary_, amount_);
        emit WithdrewTokens(beneficiary_, amount_);
    }

    function _pause() internal {
        require(!paused, "Already paused");
        paused = true;
        emit Paused();
    }

    function _unpause() internal {
        require(paused, "Not paused");
        paused = false;
        emit Unpaused();
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setInterestPrecision(uint256 interestPrecision_) external onlyOwner {
        require(interestPrecision_ > 0, "Precision cannot be 0");
        uint256 prevValue = interestPrecision;
        interestPrecision = interestPrecision_;
        emit InterestPrecisionChanged(prevValue, interestPrecision);
    }

    function nextDripAt(address claimerAddress) public view returns (uint256) {
        require(stakes[claimerAddress].staked == true, "Address has not staked");
        return stakes[claimerAddress].lastRedeemedAt + redeemInterval;
    }

    function canWithdrawStakeIn(address staker) public view returns (uint256) {
        require(stakes[staker].exists, "Stakeholder does not exist");
        require(stakes[staker].staked == false, "Stakeholder still has stake");
        uint256 unstakeTenure = block.timestamp - stakes[staker].unstakedTime;
        if (coolOff < unstakeTenure) return 0;
        return coolOff - unstakeTenure;
    }
} 