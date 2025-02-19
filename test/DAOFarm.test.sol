// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "../src/DAOFarm.sol";
import "../src/DAOFarmFactory.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./mocks/MockERC20.sol";

contract DAOFarmTest is Test {
    DAOFarmFactory public factory;
    DAOFarm public farm;
    address public owner;
    address public emergencyRecoveryAddress;
    address public feeAddress;
    address public user1;
    address public user2;

    MockERC20 public depositToken;
    MockERC20 public rewardsToken;

    uint256 public constant INITIAL_SUPPLY = 1000000 * 1e18;
    uint256 public constant REWARDS_AMOUNT = 100000 * 1e18;
    uint256 public constant USER_DEPOSIT = 1000 * 1e18;

    event ActivateEmergencyClose();
    event AddRewardsToken1(uint256 amount, uint256 feeAmount);
    event Deposit(address indexed userAddress, uint256 amount);
    event Harvest(address indexed userAddress, IERC20 rewardsToken, uint256 pending);
    event SetDateSettings(uint256 endTime);
    event UpdatePool();
    event Withdraw(address indexed userAddress, uint256 amount);
    event EmergencyWithdraw(address indexed userAddress, uint256 amount);
    event WithdrawRewardsToken1(uint256 amount, uint256 totalRewardsAmount);

    function setUp() public {
        owner = address(this);
        emergencyRecoveryAddress = address(0x1);
        feeAddress = address(0x2);
        user1 = address(0x3);
        user2 = address(0x4);

        // Deploy mock tokens
        depositToken = new MockERC20("Deposit Token", "DT", INITIAL_SUPPLY);
        rewardsToken = new MockERC20("Rewards Token", "RT", INITIAL_SUPPLY);

        // Deploy factory and farm
        factory = new DAOFarmFactory(emergencyRecoveryAddress, feeAddress);

        DAOFarm.Settings memory settings =
            DAOFarm.Settings({startTime: block.timestamp + 1 hours, endTime: block.timestamp + 1 days});

        address farmAddress =
            factory.createNitroPool(IERC20(address(depositToken)), IERC20(address(rewardsToken)), settings);
        farm = DAOFarm(farmAddress);

        // Approve tokens for testing
        depositToken.approve(address(farm), type(uint256).max);
        rewardsToken.approve(address(farm), type(uint256).max);

        // Give tokens to test users
        depositToken.transfer(user1, USER_DEPOSIT);
        depositToken.transfer(user2, USER_DEPOSIT);
        vm.prank(user1);
        depositToken.approve(address(farm), type(uint256).max);
        vm.prank(user2);
        depositToken.approve(address(farm), type(uint256).max);
    }

    // Test initial state
    function testInitialState() public {
        assertEq(address(farm.factory()), address(factory), "Wrong factory");
        assertEq(address(farm.depositToken()), address(depositToken), "Wrong deposit token");
        (IERC20 rewardsToken1,,,) = farm.rewardsToken1();
        assertEq(address(rewardsToken1), address(rewardsToken), "Wrong rewards token");
        assertEq(farm.owner(), owner, "Wrong owner");
        assertEq(farm.totalDepositAmount(), 0, "Initial deposit amount should be 0");

        (uint256 startTime,) = farm.settings();
        assertEq(farm.lastRewardTime(), startTime, "Wrong last reward time");
    }

    // ====== DEPOSIT FUNCTION TESTS ======

    function testDepositBasicFlow() public {
        (uint256 startTime,) = farm.settings();
        vm.warp(startTime);

        uint256 balanceBefore = depositToken.balanceOf(address(farm));
        uint256 userBalanceBefore = depositToken.balanceOf(user1);

        vm.expectEmit(true, false, false, true);
        emit Deposit(user1, USER_DEPOSIT);

        vm.prank(user1);
        farm.deposit(USER_DEPOSIT);

        // Check user info updated correctly
        (uint256 totalDeposit, uint256 rewardDebt) = farm.userInfo(user1);
        assertEq(totalDeposit, USER_DEPOSIT, "Wrong deposit amount in user info");
        assertEq(rewardDebt, 0, "Initial reward debt should be 0");

        // Check total deposit updated
        assertEq(farm.totalDepositAmount(), USER_DEPOSIT, "Wrong total deposit amount");

        // Check token transfers
        assertEq(depositToken.balanceOf(address(farm)) - balanceBefore, USER_DEPOSIT, "Wrong contract balance change");
        assertEq(userBalanceBefore - depositToken.balanceOf(user1), USER_DEPOSIT, "Wrong user balance change");
    }

    function testDepositMultipleTimes() public {
        (uint256 startTime,) = farm.settings();
        vm.warp(startTime);

        // First deposit
        vm.prank(user1);
        farm.deposit(USER_DEPOSIT / 2);

        (uint256 totalDepositFirst, uint256 rewardDebtFirst) = farm.userInfo(user1);
        assertEq(totalDepositFirst, USER_DEPOSIT / 2, "Wrong first deposit amount");
        assertEq(rewardDebtFirst, 0, "Wrong first reward debt");

        // Second deposit
        vm.prank(user1);
        farm.deposit(USER_DEPOSIT / 2);

        (uint256 totalDepositSecond, uint256 rewardDebtSecond) = farm.userInfo(user1);
        assertEq(totalDepositSecond, USER_DEPOSIT, "Wrong total deposit after second deposit");
        assertTrue(rewardDebtSecond >= rewardDebtFirst, "Reward debt should not decrease");
        assertEq(farm.totalDepositAmount(), USER_DEPOSIT, "Wrong total deposit amount");
    }

    function testDepositWithExistingRewards() public {
        // Add initial rewards
        farm.addRewards(REWARDS_AMOUNT);

        (uint256 startTime,) = farm.settings();
        vm.warp(startTime);

        // First user deposits
        vm.prank(user1);
        farm.deposit(USER_DEPOSIT);

        // Wait some time to accumulate rewards
        vm.warp(block.timestamp + 1 hours);

        // Second user deposits
        uint256 pendingRewardsBeforeDeposit = farm.pendingRewards(user2);
        assertEq(pendingRewardsBeforeDeposit, 0, "Should have no rewards before deposit");

        vm.prank(user2);
        farm.deposit(USER_DEPOSIT);

        (uint256 totalDeposit, uint256 rewardDebt) = farm.userInfo(user2);
        assertEq(totalDeposit, USER_DEPOSIT, "Wrong deposit amount");
        assertTrue(rewardDebt > 0, "Reward debt should be set for new deposit");

        // Check rewards are tracked correctly from deposit point
        vm.warp(block.timestamp + 1 hours);
        uint256 pendingRewards = farm.pendingRewards(user2);
        assertTrue(pendingRewards > 0, "Should accumulate rewards after deposit");
    }

    function testDepositZeroAmount() public {
        (uint256 startTime,) = farm.settings();
        vm.warp(startTime);

        vm.prank(user1);
        farm.deposit(0);

        (uint256 totalDeposit,) = farm.userInfo(user1);
        assertEq(totalDeposit, 0, "Deposit amount should be 0");
        assertEq(farm.totalDepositAmount(), 0, "Total deposit should be 0");
    }

    function testDepositAfterEndTime() public {
        (, uint256 endTime) = farm.settings();
        vm.warp(endTime + 1); // One second after end

        vm.expectRevert("not allowed");
        vm.prank(user1);
        farm.deposit(USER_DEPOSIT);

        (uint256 totalDeposit,) = farm.userInfo(user1);
        assertEq(totalDeposit, 0, "No deposit should be recorded");
        assertEq(farm.totalDepositAmount(), 0, "Total deposit should be 0");
    }

    function testDepositDuringEmergencyClose() public {
        (uint256 startTime,) = farm.settings();
        vm.warp(startTime);

        // Activate emergency close
        farm.activateEmergencyClose();

        vm.expectRevert("not allowed");
        vm.prank(user1);
        farm.deposit(USER_DEPOSIT);

        (uint256 totalDeposit,) = farm.userInfo(user1);
        assertEq(totalDeposit, 0, "No deposit should be recorded");
        assertEq(farm.totalDepositAmount(), 0, "Total deposit should be 0");
    }

    function testDepositWithInsufficientBalance() public {
        (uint256 startTime,) = farm.settings();
        vm.warp(startTime);

        uint256 largeAmount = INITIAL_SUPPLY + 1;
        vm.expectRevert(); // ERC20 insufficient balance revert
        vm.prank(user1);
        farm.deposit(largeAmount);

        (uint256 totalDeposit,) = farm.userInfo(user1);
        assertEq(totalDeposit, 0, "No deposit should be recorded");
        assertEq(farm.totalDepositAmount(), 0, "Total deposit should be 0");
    }

    function testDepositWithoutApproval() public {
        (uint256 startTime,) = farm.settings();
        vm.warp(startTime);

        // Create new user without approval
        address newUser = address(0x123);
        depositToken.transfer(newUser, USER_DEPOSIT);

        vm.expectRevert(); // ERC20 insufficient allowance revert
        vm.prank(newUser);
        farm.deposit(USER_DEPOSIT);

        (uint256 totalDeposit,) = farm.userInfo(newUser);
        assertEq(totalDeposit, 0, "No deposit should be recorded");
        assertEq(farm.totalDepositAmount(), 0, "Total deposit should be 0");
    }

    // Test rewards distribution
    function testRewardsDistribution() public {
        // Add rewards
        farm.addRewards(REWARDS_AMOUNT);

        // Fast forward to start time
        (uint256 startTime, uint256 endTime) = farm.settings();
        vm.warp(startTime);

        // User1 deposits
        vm.prank(user1);
        farm.deposit(USER_DEPOSIT);

        // Fast forward 12 hours
        vm.warp(block.timestamp + 12 hours);

        // Calculate expected rewards
        uint256 timeElapsed = 12 hours;
        uint256 expectedRewards = (REWARDS_AMOUNT * timeElapsed) / (endTime - startTime);

        uint256 pendingRewards = farm.pendingRewards(user1);
        assertApproxEqRel(pendingRewards, expectedRewards, 1e16, "Wrong pending rewards"); // 1% tolerance
    }

    function testRewardsDistributionMultipleUsers() public {
        // Add rewards
        farm.addRewards(REWARDS_AMOUNT);

        // Fast forward to start time
        (uint256 startTime, uint256 endTime) = farm.settings();
        vm.warp(startTime);

        // User1 deposits
        vm.prank(user1);
        farm.deposit(USER_DEPOSIT);

        // Fast forward 6 hours
        vm.warp(block.timestamp + 6 hours);

        // User2 deposits
        vm.prank(user2);
        farm.deposit(USER_DEPOSIT);

        // Fast forward another 6 hours
        vm.warp(block.timestamp + 6 hours);

        // Calculate expected rewards
        uint256 totalTime = 12 hours;
        uint256 user1OnlyTime = 6 hours;
        uint256 sharedTime = 6 hours;

        uint256 totalRewardsRate = REWARDS_AMOUNT / (endTime - startTime);
        uint256 user1OnlyRewards = totalRewardsRate * user1OnlyTime;
        uint256 sharedRewards = totalRewardsRate * sharedTime;

        uint256 expectedUser1Rewards = user1OnlyRewards + (sharedRewards / 2);
        uint256 expectedUser2Rewards = sharedRewards / 2;

        uint256 pendingUser1 = farm.pendingRewards(user1);
        uint256 pendingUser2 = farm.pendingRewards(user2);

        assertApproxEqRel(pendingUser1, expectedUser1Rewards, 1e16, "Wrong user1 rewards"); // 1% tolerance
        assertApproxEqRel(pendingUser2, expectedUser2Rewards, 1e16, "Wrong user2 rewards"); // 1% tolerance
    }

    // Test harvest functionality
    function testHarvest() public {
        // Add rewards
        farm.addRewards(REWARDS_AMOUNT);

        // Fast forward to start time
        (uint256 startTime,) = farm.settings();
        vm.warp(startTime);

        // User1 deposits
        vm.prank(user1);
        farm.deposit(USER_DEPOSIT);

        // Fast forward 12 hours
        vm.warp(block.timestamp + 12 hours);

        uint256 pendingBefore = farm.pendingRewards(user1);
        uint256 balanceBefore = rewardsToken.balanceOf(user1);

        vm.prank(user1);
        farm.harvest();

        uint256 balanceAfter = rewardsToken.balanceOf(user1);
        assertEq(balanceAfter - balanceBefore, pendingBefore, "Wrong harvested amount");
        assertEq(farm.pendingRewards(user1), 0, "Pending rewards should be 0 after harvest");
    }

    // Test withdraw functionality
    function testWithdraw() public {
        // Setup initial deposit
        (uint256 startTime, uint256 endTime) = farm.settings();
        vm.warp(startTime);
        vm.prank(user1);
        farm.deposit(USER_DEPOSIT);

        // Fast forward some time
        vm.warp(block.timestamp + 12 hours);

        uint256 pendingBefore = farm.pendingRewards(user1);
        uint256 rewardsBalanceBefore = rewardsToken.balanceOf(user1);
        uint256 depositBalanceBefore = depositToken.balanceOf(user1);

        vm.warp(endTime);
        vm.prank(user1);
        farm.withdraw(USER_DEPOSIT);

        uint256 rewardsBalanceAfter = rewardsToken.balanceOf(user1);
        uint256 depositBalanceAfter = depositToken.balanceOf(user1);

        assertEq(rewardsBalanceAfter - rewardsBalanceBefore, pendingBefore, "Wrong rewards amount");
        assertEq(depositBalanceAfter - depositBalanceBefore, USER_DEPOSIT, "Wrong withdraw amount");
        assertEq(farm.totalDepositAmount(), 0, "Total deposit should be 0");
    }

    function testWithdrawTooMuchReverts() public {
        (uint256 startTime, uint256 endTime) = farm.settings();
        vm.warp(startTime);
        vm.prank(user1);
        farm.deposit(USER_DEPOSIT);

        vm.warp(endTime);
        vm.expectRevert("Withdrawing too much");
        vm.prank(user1);
        farm.withdraw(USER_DEPOSIT + 1);
    }

    // Test emergency withdraw
    function testEmergencyWithdraw() public {
        (uint256 startTime,) = farm.settings();
        vm.warp(startTime);
        vm.prank(user1);
        farm.deposit(USER_DEPOSIT);

        uint256 balanceBefore = depositToken.balanceOf(user1);

        vm.prank(user1);
        farm.emergencyWithdraw();

        uint256 balanceAfter = depositToken.balanceOf(user1);
        assertEq(balanceAfter - balanceBefore, USER_DEPOSIT, "Wrong emergency withdraw amount");
        assertEq(farm.totalDepositAmount(), 0, "Total deposit should be 0");

        (uint256 userDeposit,) = farm.userInfo(user1);
        assertEq(userDeposit, 0, "User deposit should be 0");
    }

    // Test emergency close
    function testEmergencyClose() public {
        // Add rewards
        farm.addRewards(REWARDS_AMOUNT);

        (,, uint256 remainingAmountBefore,) = farm.rewardsToken1();

        vm.expectEmit(true, false, false, true);
        emit ActivateEmergencyClose();

        farm.activateEmergencyClose();

        assertTrue(farm.emergencyClose(), "Emergency close should be active");
        (,, uint256 remainingAmountAfter,) = farm.rewardsToken1();

        assertEq(remainingAmountAfter, 0, "Remaining rewards should be 0");
        assertEq(
            rewardsToken.balanceOf(emergencyRecoveryAddress), remainingAmountBefore, "Wrong emergency recovery amount"
        );
    }

    // Test rewards withdrawal before start
    function testWithdrawRewardsBeforeStart() public {
        // Add rewards
        farm.addRewards(REWARDS_AMOUNT);

        uint256 balanceBefore = rewardsToken.balanceOf(owner);

        vm.expectEmit(true, false, false, true);
        emit WithdrawRewardsToken1(REWARDS_AMOUNT, 0);

        farm.withdrawRewards(REWARDS_AMOUNT);

        uint256 balanceAfter = rewardsToken.balanceOf(owner);
        assertEq(balanceAfter - balanceBefore, REWARDS_AMOUNT, "Wrong withdrawn rewards amount");
        (,, uint256 remainingAmountAfter,) = farm.rewardsToken1();
        assertEq(remainingAmountAfter, 0, "Remaining rewards should be 0");
    }

    // Test date settings
    function testSetDateSettings() public {
        (, uint256 endTimeBefore) = farm.settings();
        uint256 newEndTime = endTimeBefore + 1 days;

        farm.setDateSettings(newEndTime);

        (, uint256 endTimeAfter) = farm.settings();
        assertEq(endTimeAfter, newEndTime, "Wrong new end time");
    }

    function testSetDateSettingsInvalidTimeReverts() public {
        (uint256 startTime,) = farm.settings();
        vm.expectRevert("invalid endTime");
        farm.setDateSettings(startTime - 1);
    }

    function testSetDateSettingsAfterEndReverts() public {
        (, uint256 endTime) = farm.settings();
        // Warp to after end time
        vm.warp(endTime + 1);

        vm.expectRevert(bytes("pool ended"));
        farm.setDateSettings(endTime + 1 days);
    }

    // ====== REWARDS CALCULATION TESTS ======

    function testRewardsToken1PerSecond() public {
        // Add rewards
        farm.addRewards(REWARDS_AMOUNT);

        (uint256 startTime, uint256 endTime) = farm.settings();
        uint256 duration = endTime - startTime;

        // Test before start
        assertEq(farm.rewardsToken1PerSecond(), REWARDS_AMOUNT / duration, "Wrong rewards per second before start");

        // Test during rewards period
        vm.warp(startTime + duration / 2);
        assertEq(farm.rewardsToken1PerSecond(), REWARDS_AMOUNT / duration, "Wrong rewards per second during period");

        // Test after end
        vm.warp(endTime + 1);
        farm.updatePool(); // update pool to set lastRewardTime
        assertEq(farm.rewardsToken1PerSecond(), 0, "Rewards per second should be 0 after end");
    }

    function testPendingRewardsNoDeposits() public {
        farm.addRewards(REWARDS_AMOUNT);

        (uint256 startTime,) = farm.settings();
        vm.warp(startTime + 1 hours);

        uint256 pending = farm.pendingRewards(user1);
        assertEq(pending, 0, "Should have no rewards without deposits");
    }

    function testPendingRewardsSingleUser() public {
        farm.addRewards(REWARDS_AMOUNT);

        (uint256 startTime, uint256 endTime) = farm.settings();
        vm.warp(startTime);

        // User deposits
        vm.prank(user1);
        farm.deposit(USER_DEPOSIT);

        // Move forward 6 hours
        vm.warp(startTime + 6 hours);

        uint256 expectedRewards = (REWARDS_AMOUNT * 6 hours) / (endTime - startTime);
        uint256 pending = farm.pendingRewards(user1);

        assertApproxEqRel(pending, expectedRewards, 1e16, "Wrong pending rewards calculation");
    }

    function testPendingRewardsAfterPartialWithdraw() public {
        farm.addRewards(REWARDS_AMOUNT);

        (uint256 startTime, uint256 endTime) = farm.settings();
        vm.warp(startTime);

        // User deposits
        vm.prank(user1);
        farm.deposit(USER_DEPOSIT);

        // Move forward 6 hours
        vm.warp(endTime);

        // Partial withdraw
        vm.prank(user1);
        farm.withdraw(USER_DEPOSIT / 2);


        uint256 pending = farm.pendingRewards(user1);
        assertTrue(pending == 0, "Should not have pending rewards after partial withdraw");
    }

    // ====== ADD REWARDS TESTS ======

    function testAddRewardsBasic() public {
        uint256 amount = REWARDS_AMOUNT;

        vm.expectEmit(true, false, false, true);
        emit AddRewardsToken1(amount, 0); // No fee in test setup

        farm.addRewards(amount);

        (, uint256 totalAmount, uint256 remainingAmount,) = farm.rewardsToken1();
        assertEq(totalAmount, amount, "Wrong total rewards amount");
        assertEq(remainingAmount, amount, "Wrong remaining rewards amount");
    }

    function testAddRewardsMultipleTimes() public {
        uint256 amount1 = REWARDS_AMOUNT / 2;
        uint256 amount2 = REWARDS_AMOUNT / 2;

        farm.addRewards(amount1);
        farm.addRewards(amount2);

        (, uint256 totalAmount, uint256 remainingAmount,) = farm.rewardsToken1();
        assertEq(totalAmount, REWARDS_AMOUNT, "Wrong total rewards amount");
        assertEq(remainingAmount, REWARDS_AMOUNT, "Wrong remaining rewards amount");
    }

    function testAddRewardsAfterPoolEnded() public {
        (, uint256 endTime) = farm.settings();
        vm.warp(endTime + 1);

        vm.expectRevert("pool ended");
        farm.addRewards(REWARDS_AMOUNT);
    }

    function testAddRewardsWithFee() public {
        // Set fee in factory
        factory.setDefaultFee(500); // 5% fee

        uint256 amount = REWARDS_AMOUNT;
        uint256 expectedFee = amount * 500 / 10000;
        uint256 expectedAmount = amount - expectedFee;

        vm.expectEmit(true, false, false, true);
        emit AddRewardsToken1(expectedAmount, expectedFee);

        farm.addRewards(amount);

        // Check fee transfer
        assertEq(rewardsToken.balanceOf(feeAddress), expectedFee, "Wrong fee transfer");

        // Check rewards update
        (, uint256 totalAmount, uint256 remainingAmount,) = farm.rewardsToken1();
        assertEq(totalAmount, expectedAmount, "Wrong total rewards amount");
        assertEq(remainingAmount, expectedAmount, "Wrong remaining rewards amount");
    }

    // ====== HARVEST TESTS ======

    function testHarvestWithNoRewards() public {
        (uint256 startTime,) = farm.settings();
        vm.warp(startTime);

        vm.prank(user1);
        farm.deposit(USER_DEPOSIT);

        uint256 balanceBefore = rewardsToken.balanceOf(user1);

        vm.prank(user1);
        farm.harvest();

        uint256 balanceAfter = rewardsToken.balanceOf(user1);
        assertEq(balanceAfter, balanceBefore, "No rewards should be harvested");
    }

    function testHarvestWithMultipleUsers() public {
        farm.addRewards(REWARDS_AMOUNT);

        (uint256 startTime,) = farm.settings();
        vm.warp(startTime);

        // Both users deposit
        vm.prank(user1);
        farm.deposit(USER_DEPOSIT);
        vm.prank(user2);
        farm.deposit(USER_DEPOSIT);

        // Move forward
        vm.warp(startTime + 12 hours);

        // Both users harvest
        uint256 user1BalanceBefore = rewardsToken.balanceOf(user1);
        uint256 user2BalanceBefore = rewardsToken.balanceOf(user2);

        vm.prank(user1);
        farm.harvest();
        vm.prank(user2);
        farm.harvest();

        uint256 user1Rewards = rewardsToken.balanceOf(user1) - user1BalanceBefore;
        uint256 user2Rewards = rewardsToken.balanceOf(user2) - user2BalanceBefore;

        assertApproxEqRel(user1Rewards, user2Rewards, 1e16, "Users should receive equal rewards");
    }

    function testHarvestMultipleTimes() public {
        farm.addRewards(REWARDS_AMOUNT);

        (uint256 startTime,) = farm.settings();
        vm.warp(startTime);

        vm.prank(user1);
        farm.deposit(USER_DEPOSIT);

        // First harvest after 6 hours
        vm.warp(startTime + 6 hours);
        uint256 balanceBefore = rewardsToken.balanceOf(user1);

        vm.prank(user1);
        farm.harvest();

        uint256 firstHarvestAmount = rewardsToken.balanceOf(user1) - balanceBefore;
        assertTrue(firstHarvestAmount > 0, "First harvest should yield rewards");

        // Second harvest after another 6 hours
        vm.warp(startTime + 12 hours);
        balanceBefore = rewardsToken.balanceOf(user1);

        vm.prank(user1);
        farm.harvest();

        uint256 secondHarvestAmount = rewardsToken.balanceOf(user1) - balanceBefore;
        assertTrue(secondHarvestAmount > 0, "Second harvest should yield rewards");
        assertApproxEqRel(firstHarvestAmount, secondHarvestAmount, 1e16, "Harvest amounts should be similar");
    }

    // ====== UPDATE POOL TESTS ======

    function testUpdatePoolNoDeposits() public {
        farm.addRewards(REWARDS_AMOUNT);

        (uint256 startTime,) = farm.settings();
        vm.warp(startTime + 1 hours);

        vm.expectEmit(true, false, false, true);
        emit UpdatePool();

        farm.updatePool();

        assertEq(farm.lastRewardTime(), startTime + 1 hours, "Last reward time should be updated");
    }

    function testUpdatePoolWithDeposits() public {
        farm.addRewards(REWARDS_AMOUNT);

        (uint256 startTime,) = farm.settings();
        vm.warp(startTime);

        vm.prank(user1);
        farm.deposit(USER_DEPOSIT);

        vm.warp(startTime + 1 hours);

        (,, uint256 remainingBefore, uint256 accRewardsPerShareBefore) = farm.rewardsToken1();

        farm.updatePool();

        (,, uint256 remainingAfter, uint256 accRewardsPerShareAfter) = farm.rewardsToken1();

        assertTrue(remainingAfter < remainingBefore, "Remaining rewards should decrease");
        assertTrue(accRewardsPerShareAfter > accRewardsPerShareBefore, "Accumulated rewards should increase");
    }

    function testUpdatePoolAfterEnd() public {
        farm.addRewards(REWARDS_AMOUNT);

        (, uint256 endTime) = farm.settings();
        vm.warp(endTime + 1);

        (,, uint256 remainingBefore, uint256 accRewardsPerShareBefore) = farm.rewardsToken1();

        farm.updatePool();

        (,, uint256 remainingAfter, uint256 accRewardsPerShareAfter) = farm.rewardsToken1();

        assertEq(remainingAfter, remainingBefore, "Remaining rewards should not change after end");
        assertEq(accRewardsPerShareAfter, accRewardsPerShareBefore, "Accumulated rewards should not change after end");
    }

    // ====== WITHDRAW TESTS ======

    function testWithdrawBasic() public {
        (uint256 startTime, uint256 endTime) = farm.settings();
        vm.warp(startTime);

        // Initial deposit
        vm.prank(user1);
        farm.deposit(USER_DEPOSIT);

        uint256 balanceBefore = depositToken.balanceOf(user1);

        vm.expectEmit(true, false, false, true);
        emit Withdraw(user1, USER_DEPOSIT);

        vm.warp(endTime);
        vm.prank(user1);
        farm.withdraw(USER_DEPOSIT);

        // Check token transfer
        assertEq(depositToken.balanceOf(user1) - balanceBefore, USER_DEPOSIT, "Wrong withdraw amount");

        // Check state updates
        (uint256 userDeposit,) = farm.userInfo(user1);
        assertEq(userDeposit, 0, "User deposit should be 0");
        assertEq(farm.totalDepositAmount(), 0, "Total deposit should be 0");
    }

    function testWithdrawPartial() public {
        (uint256 startTime, uint256 endTime) = farm.settings();
        vm.warp(startTime);

        // Initial deposit
        vm.prank(user1);
        farm.deposit(USER_DEPOSIT);

        uint256 withdrawAmount = USER_DEPOSIT / 2;
        uint256 balanceBefore = depositToken.balanceOf(user1);

        vm.warp(endTime);
        vm.prank(user1);
        farm.withdraw(withdrawAmount);

        // Check token transfer
        assertEq(depositToken.balanceOf(user1) - balanceBefore, withdrawAmount, "Wrong withdraw amount");

        // Check state updates
        (uint256 userDeposit,) = farm.userInfo(user1);
        assertEq(userDeposit, USER_DEPOSIT - withdrawAmount, "Wrong remaining deposit");
        assertEq(farm.totalDepositAmount(), USER_DEPOSIT - withdrawAmount, "Wrong total deposit");
    }

    function testWithdrawWithPendingRewards() public {
        farm.addRewards(REWARDS_AMOUNT);

        (uint256 startTime, uint256 endTime) = farm.settings();
        vm.warp(startTime);

        // Initial deposit
        vm.prank(user1);
        farm.deposit(USER_DEPOSIT);

        // Move forward to accumulate rewards
        vm.warp(endTime);

        uint256 pendingBefore = farm.pendingRewards(user1);
        uint256 rewardsBalanceBefore = rewardsToken.balanceOf(user1);

        vm.prank(user1);
        farm.withdraw(USER_DEPOSIT);

        // Check rewards transfer
        assertEq(rewardsToken.balanceOf(user1) - rewardsBalanceBefore, pendingBefore, "Wrong rewards amount");
    }

    // ====== EMERGENCY WITHDRAW TESTS ======

    function testEmergencyWithdrawBasic() public {
        (uint256 startTime,) = farm.settings();
        vm.warp(startTime);

        // Initial deposit
        vm.prank(user1);
        farm.deposit(USER_DEPOSIT);

        uint256 balanceBefore = depositToken.balanceOf(user1);

        vm.expectEmit(true, false, false, true);
        emit EmergencyWithdraw(user1, USER_DEPOSIT);

        vm.prank(user1);
        farm.emergencyWithdraw();

        // Check token transfer
        assertEq(depositToken.balanceOf(user1) - balanceBefore, USER_DEPOSIT, "Wrong withdraw amount");

        // Check state updates
        (uint256 userDeposit,) = farm.userInfo(user1);
        assertEq(userDeposit, 0, "User deposit should be 0");
        assertEq(farm.totalDepositAmount(), 0, "Total deposit should be 0");
    }

    function testEmergencyWithdrawWithPendingRewards() public {
        farm.addRewards(REWARDS_AMOUNT);

        (uint256 startTime,) = farm.settings();
        vm.warp(startTime);

        // Initial deposit
        vm.prank(user1);
        farm.deposit(USER_DEPOSIT);

        // Move forward to accumulate rewards
        vm.warp(startTime + 12 hours);

        uint256 rewardsBalanceBefore = rewardsToken.balanceOf(user1);

        vm.prank(user1);
        farm.emergencyWithdraw();

        // Check no rewards transfer
        assertEq(
            rewardsToken.balanceOf(user1), rewardsBalanceBefore, "Should not receive rewards in emergency withdraw"
        );
    }

    // ====== OWNERSHIP TESTS ======

    function testTransferOwnership() public {
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferred(owner, user1);

        farm.transferOwnership(user1);

        assertEq(farm.owner(), user1, "Wrong new owner");
    }

    function testTransferOwnershipUpdatesFactory() public {
        farm.transferOwnership(user1);

        assertEq(factory.ownerNitroPoolsLength(owner), 0, "Old owner should have no pools");
        assertEq(factory.ownerNitroPoolsLength(user1), 1, "New owner should have one pool");
        assertEq(factory.getOwnerNitroPool(user1, 0), address(farm), "Wrong pool address for new owner");
    }

    function testRenounceOwnership() public {
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferred(owner, address(0));

        farm.renounceOwnership();

        assertEq(farm.owner(), address(0), "Owner should be zero address");
        assertEq(factory.ownerNitroPoolsLength(owner), 0, "Previous owner should have no pools");
    }

    // ====== SAFE TRANSFER TESTS ======

    function testSafeRewardsTransfer() public {
        farm.addRewards(REWARDS_AMOUNT);

        (uint256 startTime,) = farm.settings();
        vm.warp(startTime);

        // Initial deposit
        vm.prank(user1);
        farm.deposit(USER_DEPOSIT);

        // Move forward to accumulate rewards
        vm.warp(startTime + 12 hours);

        // Remove some rewards tokens to test safe transfer
        uint256 pendingRewards = farm.pendingRewards(user1);
        vm.prank(address(farm));
        rewardsToken.transfer(address(0x999), REWARDS_AMOUNT - pendingRewards / 2);

        vm.prank(user1);
        farm.harvest();

        // Should receive only available balance
        assertEq(rewardsToken.balanceOf(user1), pendingRewards / 2, "Should receive only available rewards");
    }

    // ====== DATE SETTINGS TESTS ======

    function testSetDateSettingsBasic() public {
        (uint256 startTime, uint256 oldEndTime) = farm.settings();
        uint256 newEndTime = oldEndTime + 1 days;

        vm.expectEmit(true, false, false, true);
        emit SetDateSettings(newEndTime);

        farm.setDateSettings(newEndTime);

        (, uint256 endTimeAfter) = farm.settings();
        assertEq(endTimeAfter, newEndTime, "Wrong new end time");
    }

    function testSetDateSettingsUpdatesRewardRate() public {
        farm.addRewards(REWARDS_AMOUNT);

        (uint256 startTime, uint256 oldEndTime) = farm.settings();
        uint256 oldRewardRate = farm.rewardsToken1PerSecond();

        uint256 newEndTime = oldEndTime + 1 days;
        farm.setDateSettings(newEndTime);

        uint256 newRewardRate = farm.rewardsToken1PerSecond();
        assertTrue(newRewardRate < oldRewardRate, "Reward rate should decrease with longer duration");
    }

    function testSetDateSettingsOnlyOwner() public {
        (, uint256 endTime) = farm.settings();

        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        farm.setDateSettings(endTime + 1 days);
    }

    // ====== INTEGRATION TESTS ======

    function testFullLifecycle() public {
        // 1. Add initial rewards
        farm.addRewards(REWARDS_AMOUNT);

        (uint256 startTime, uint256 endTime) = farm.settings();
        vm.warp(startTime);

        // 2. Users deposit
        vm.prank(user1);
        farm.deposit(USER_DEPOSIT);
        vm.prank(user2);
        farm.deposit(USER_DEPOSIT);

        // 3. Time passes, rewards accumulate
        vm.warp(startTime + 6 hours);

        // 4. User1 harvests
        uint256 user1BalanceBefore = rewardsToken.balanceOf(user1);
        vm.prank(user1);
        farm.harvest();
        uint256 user1Rewards = rewardsToken.balanceOf(user1) - user1BalanceBefore;

        uint256 user2BalanceBefore = rewardsToken.balanceOf(user2);
        vm.prank(user2);
        farm.harvest();
        uint256 user2Rewards = rewardsToken.balanceOf(user2) - user2BalanceBefore;

        // 5. More time passes
        vm.warp(endTime);


        // 6. User withdraws (should get rewards too)
        uint256 user1BalanceAfter = rewardsToken.balanceOf(user1);
        vm.prank(user1);
        farm.withdraw(USER_DEPOSIT);
        uint256 user1RewardsAfter = rewardsToken.balanceOf(user1) - user1BalanceAfter;

        uint256 user2BalanceAfter = rewardsToken.balanceOf(user2);
        vm.prank(user2);
        farm.withdraw(USER_DEPOSIT);
        uint256 user2RewardsAfter = rewardsToken.balanceOf(user2) - user2BalanceAfter;

        // 7. Verify final state
        assertTrue(user1Rewards > 0, "User1 should have rewards");
        assertTrue(user2Rewards > 0, "User2 should have rewards");
        assertApproxEqRel(user1Rewards, user2Rewards, 1e16, "Users should have similar rewards");

        assertTrue(user1RewardsAfter > 0, "User1 should have rewards");
        assertTrue(user2RewardsAfter > 0, "User2 should have rewards");
        assertApproxEqRel(user1RewardsAfter, user2RewardsAfter, 1e16, "Users should have similar rewards");
    }

    function testEmergencyScenario() public {
        // 1. Add rewards and setup
        farm.addRewards(REWARDS_AMOUNT);

        (uint256 startTime,) = farm.settings();
        vm.warp(startTime);

        // 2. Users deposit
        vm.prank(user1);
        farm.deposit(USER_DEPOSIT);
        vm.prank(user2);
        farm.deposit(USER_DEPOSIT);

        // 3. Time passes
        vm.warp(startTime + 6 hours);

        // 4. Emergency occurs
        farm.activateEmergencyClose();

        // 5. Users emergency withdraw
        vm.prank(user1);
        farm.emergencyWithdraw();
        vm.prank(user2);
        farm.emergencyWithdraw();

        // 6. Verify final state
        assertEq(farm.totalDepositAmount(), 0, "All deposits should be withdrawn");
        assertEq(depositToken.balanceOf(user1), USER_DEPOSIT, "User1 should have their deposit back");
        assertEq(depositToken.balanceOf(user2), USER_DEPOSIT, "User2 should have their deposit back");
        assertTrue(rewardsToken.balanceOf(emergencyRecoveryAddress) > 0, "Emergency address should have rewards");
    }

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
}
