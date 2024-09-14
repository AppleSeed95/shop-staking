// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "../src/XShop.sol";
import "./UniswapV2Mock.sol";
import "./ShopMock.sol";

contract XShopTest is Test {
    XShop public xshop;
    SHOP public shop;
    uint256 initialSupply = 10 ** 24; // 1M tokens, 18 decimals
    address internal constant anotherUser = address(71);
    uint256 depositAmount = 25000 * 1e18;


    function setUp() public {
        xshop = new XShop();
        SHOP shopToken = new SHOP();
        vm.etch(address(0x99e186E8671DB8B10d45B7A1C430952a9FBE0D40), address(shopToken).code);
        shop = SHOP(payable(0x99e186E8671DB8B10d45B7A1C430952a9FBE0D40));
        UniswapV2Mock router = new UniswapV2Mock();
        vm.etch(address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D), address(router).code);
        shop.mint(address(this), initialSupply);
        shop.mint(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D, 100000 * 1e18);
        shop.approve(address(xshop), initialSupply);
    }

    function testInitialization() public {
        // Check initial parameters
        assert(xshop.minimumStake() == 20000 * 10 ** 18);
        assert(xshop.timeLock() == 5 days);
        assert(xshop.epochDuration() == 1 days);
    }

    function testDeposit() public {
        // Approve XShop to transfer SHOP
        uint256 shopBalance = shop.balanceOf(address(this));
        // Deposit into XShop
        xshop.deposit(depositAmount);

        // Validate the deposit
        assertEq(xshop.balanceOf(address(this)), depositAmount);
        assertEq(shop.balanceOf(address(this)), shopBalance - depositAmount);
        // Validate totalsupply change
        assertEq(xshop.totalSupply(), depositAmount);
    }

    function testFailMinimumAllowableDeposit() public {
        xshop.deposit(19000 * 1e18);
    }

    function testWithdraw() public {
        uint256 withdrawAmount = 20000 * 10 ** 18;
        xshop.deposit(withdrawAmount);
        skip(5 days + 10);
        // Withdraw from XShop
        xshop.withdraw(withdrawAmount);

        xshop.deposit(withdrawAmount * 2);
        skip(5 days + 10);
        xshop.withdraw(withdrawAmount);
        assertEq(xshop.balanceOf(address(this)), withdrawAmount);

        xshop.snapshot{value: 1 ether}();
        skip(5 days + 10);
        assertEq(xshop.balanceOf(address(this)), withdrawAmount);
        xshop.withdraw(withdrawAmount);
        assertEq(xshop.balanceOf(address(this)), 0);
    }

    function testToggleReinvesting() public {
        xshop.toggleReinvesting();
        // Check the status of reinvesting
        assert(xshop.isReinvesting() == true);
    }

    function testSnapshot() public payable {
        // Create a snapshot with some eth
        xshop.snapshot{value: 1 ether}();
        // Validate the snapshot
        (uint256 timestamp, uint256 rewards,  uint256 supply, uint256 shopb, uint256 deposited, uint256 withdrawn) = xshop.epochInfo(0);
        //rewards
        assert(rewards == 1 ether);
        assert(supply == 0);
        //timestamp
        assert(timestamp > 0);
    }


    function testFailNextSnapshotTooEarly() public payable {
        // Create a snapshot with some eth
        xshop.snapshot{value: 1 ether}();
        skip(1 hours);
        xshop.snapshot{value: 1 ether}();
    }

    function testNextSnapshot() public payable {
        // Create a snapshot with some eth
        xshop.snapshot{value: 1 ether}();

        // Validate the snapshot
        (uint256 timestamp, uint256 rewards,  uint256 supply, uint256 shopb, uint256 deposited, uint256 withdrawn) = xshop.epochInfo(0);
        //rewards
        assert(rewards == 1 ether);
        assert(supply == 0);
        //timestamp
        assert(timestamp > 0);
        skip(1 days);
        xshop.snapshot{value: 2 ether}();
    }

    function testFailClaimRightAfterDeposit() public payable {
        uint256 amount = 20000 * 10 ** 18;
        xshop.deposit(amount);
        // Create a snapshot with some eth
        xshop.snapshot{value: 1 ether}();
        // Validate the snapshot
        xshop.claimReward();
    }

    function testClaim() public payable {
        // preparing a user
        shop.mint(anotherUser, 100000 * 1e18);
        vm.startPrank(anotherUser);
        shop.approve(address(xshop), initialSupply);
        vm.stopPrank();
        // Now we have 2 users - the contract (user) and anotherUser

        // ==================== epoch 0 ====================
        xshop.deposit(20000 * 1e18);
        // Skipping, just testing if the bot skips run, should be treated as epoch 0 anyways
        skip(5 days);
        xshop.deposit(20000 * 1e18);
        vm.startPrank(anotherUser);
        xshop.deposit(60000 * 1e18);
        vm.stopPrank();
        // Now the balances are: user = 40K, anotherUser = 60K, supply = 100K
        // Checking rewards:
        uint256 reward = xshop.getPendingReward();
        assertEq(reward, 0);
        // Should be no rewards, since just started
        // Distributing 1 ETH as rewards
        xshop.snapshot{value: 1 ether}();
        // Checking the balance of the contract
        assertEq(address(xshop).balance, 1 ether);

        // ==================== epoch 1 ====================
        reward = xshop.getPendingReward();
        // too early, no rewards
        assertEq(reward, 0);
        skip(1 days);
        // user = 20K, anotherUser = 60K, supply = 80K
        xshop.withdraw(20000 * 1e18);
        //0.2 ether
        xshop.snapshot{value: 2 * 1e17}();
        //should be 1.2ETh now
        assertEq(address(xshop).balance, 12 * 1e17);

        // epoch 2 started
        reward = xshop.getPendingReward();
        // User
        // 20K withdrawn, the user has zero balance how,
        // the reward is calculated from previous epochs, the reward is:
        // epoch 0:  1 ether * 40K / 100K (balances of epoch 0) = 0.4 ether
        // epoch 1:  last one
        assertEq(reward, 40 * 1e16);
        vm.startPrank(anotherUser);
        uint256 rewardanotherUser = xshop.getPendingReward();
        vm.stopPrank();
        // anotherUser
        // The reward is:
        // epoch 0:  1 ether * 60 / 100 = 0.6 ether
        // epoch 1:  last one
        assertEq(rewardanotherUser, 60 * 1e16);
        skip(1 days);
        xshop.withdraw(20000 * 1e18);
        xshop.snapshot{value: 1 ether}();
        skip(1 days);

        // ==================== epoch 3 ====================
        reward = xshop.getPendingReward();
        // epoch 0: 0.4 ether
        // epoch 1: 0.2 ether * 20/80 = 0.05 ether
        // epoch 2: last one
        assertEq(reward, 45 * 1e16);
        vm.startPrank(anotherUser);
        rewardanotherUser = xshop.getPendingReward();
        vm.stopPrank();
        // anotherUser has 60K, so the reward is:
        // epoch 0: 0.6 ether
        // epoch 1: 0.2 ether * 60/80 = 0.15 ether
        // epoch 2: last one
        assertEq(rewardanotherUser, 75 * 1e16);
        uint256 balanceBefore = address(this).balance;
        skip(1 days);
        rewardanotherUser = xshop.getPendingReward();
        xshop.claimReward();
        assertEq(address(this).balance - balanceBefore, reward);
        vm.startPrank(anotherUser);
        rewardanotherUser = xshop.getPendingReward();
        balanceBefore = address(anotherUser).balance;
        uint256 rewardAnotherUser = xshop.getPendingReward();
        xshop.claimReward();
        assertEq(address(anotherUser).balance - balanceBefore, rewardAnotherUser);
        // now rewards should be 0
        rewardAnotherUser = xshop.getPendingReward();
        assertEq(rewardAnotherUser, 0);
        vm.stopPrank();
        // now rewards should be 0
        reward = xshop.getPendingReward();
        assertEq(reward, 0);
        xshop.snapshot{value: 10 ether}();
        skip(1 days);

        // ==================== epoch 4 ====================
        xshop.deposit(20000 * 1e18);
        reward = xshop.getPendingReward();
        assertEq(reward, 0);
        // epoch 0-1: claimed
        // epoch 2: the only user gets it all, 1 ether
        // epoch 3: last one
        vm.startPrank(anotherUser);
        balanceBefore = address(anotherUser).balance;
        xshop.claimReward();
        assertEq(address(anotherUser).balance - balanceBefore, 1 ether);
        // now rewards should be 0
        vm.stopPrank();
        // anotherUser gets it in 6
        xshop.snapshot{value: 1 ether}();
        skip(1 days);

        // ==================== epoch 5 ====================
        xshop.snapshot{value: 1 ether}();
        skip(1 days);

        // ==================== epoch 6 ====================
        balanceBefore = address(this).balance;
        xshop.claimReward();
        assertEq(address(this).balance - balanceBefore, 1 ether * 20 / 80);
        //
        vm.startPrank(anotherUser);
        balanceBefore = address(anotherUser).balance;
        xshop.claimReward();
        assertEq(address(anotherUser).balance - balanceBefore, 10 ether + 1 ether * 60 / 80);
        vm.stopPrank();
    }

    function testReInvesting() public {
        // preparing a user
        shop.mint(anotherUser, 100000 * 1e18);
        vm.startPrank(anotherUser);
        shop.approve(address(xshop), initialSupply);
        vm.stopPrank();
        // Now we have 2 users - the contract (user) and anotherUser

        // ==================== epoch 0 ====================
        xshop.deposit(40000 * 1e18);
        xshop.toggleReinvesting();
        // Skipping, just testing if the bot skips run, should be treated as epoch 0 anyways
        vm.startPrank(anotherUser);
        xshop.deposit(60000 * 1e18);
        vm.stopPrank();
        // Now the balances are: user = 40K reinvested, anotherUser = 60K, supply = 100K
        xshop.snapshot{value: 1 ether}();
        // ==================== epoch 1 ====================
        skip(1 days);
        xshop.snapshot{value: 1 ether}();
        // ==================== epoch 2 ====================
        skip(1 days);
        xshop.snapshot{value: 1 ether}();
        // ==================== epoch 3 ====================
        // Here we have to get rewards from epoch 0 reinvested for the user
        assertEq(xshop.getPendingReward(), 0);
        // There should be 40/100 * 1 ETH = 0.4 ETH reinvested
        // Which is 0.4 x 100K fixed price on mock router = 40K
        // So the user should have 40K + 40K = 80K
        assertEq(xshop.balanceOf(address(this)), 80000 * 1e18);
        vm.startPrank(anotherUser);
        // anotherUser should have 60K / 100K * 1 ETH x 2 = 1.2 ETH
        assertEq(xshop.getPendingReward(), 1200000000000000000);
        vm.stopPrank();
        // turning off reinvesting
        xshop.toggleReinvesting();
        skip(1 days);
        xshop.snapshot{value: 1 ether}();
        // ==================== epoch 4 ====================
        skip(1 days);
        xshop.snapshot{value: 1 ether}();
        // ==================== epoch 5 ====================
        // Rewards are the following:
        //from epoch 3 : 80K/ (80K+60K) * 1 ETH = 0.5714285714285714 ETH
        assertEq(xshop.getPendingReward(), 571428571428571428);
        assertEq(xshop.balanceOf(address(this)), 80000 * 1e18);
        skip(1 days);
        xshop.snapshot{value: 1 ether}();
        // ==================== epoch 6 ====================
        assertEq(xshop.getPendingReward(), 1142857142857142856);
        xshop.claimReward();
        assertEq(xshop.balanceOf(address(this)), 80000 * 1e18);
        skip(1 days);
        xshop.snapshot{value: 1 ether}();
        // ==================== epoch 7 ====================
        assertEq(xshop.getPendingReward(), 571428571428571428);
        skip(1 days);
        xshop.snapshot{value: 1 ether}();
        // ==================== epoch 8 ====================
        assertEq(xshop.getPendingReward(), 1142857142857142856);
    }

    function testFailTimeLock() public payable {
        xshop.deposit(depositAmount);
        xshop.withdraw(depositAmount);
    }

    function testTimeLock() public payable {
        xshop.deposit(depositAmount);
        skip(6 days);
        xshop.withdraw(depositAmount);
    }


    receive() external payable {}

}
