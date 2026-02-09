// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {ClixpesaSavings} from "../src/savings/SavingsV1.sol";
import {DeploySavings} from "../script/DeploySavings.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {ISavings} from "../src/interfaces/ISavings.sol";

contract TestSavings is Test {
    ClixpesaSavings savings;
    DeploySavings deployer;
    HelperConfig config;

    address treasury;
    address usdc;
    address usdt;

    address public user = makeAddr("user");

    // Interest rate constants (from SavingsV1)
    uint256 private constant TIER1 = 10001725e11; // 6.5% APY
    uint256 private constant TIER2 = 10001982e11; // 7.5% APY
    uint256 private constant TIER3 = 10002361e11; // 9.0% APY

    // Expected annual multipliers (with some tolerance for rounding)
    uint256 private constant TIER1_ANNUAL = 1065e15; // 1.065 * 1e18
    uint256 private constant TIER2_ANNUAL = 1075e15; // 1.075 * 1e18
    uint256 private constant TIER3_ANNUAL = 1090e15; // 1.090 * 1e18

    uint256 public constant PSTARTING_USD_BAL = 1000e18; //Pool USD Starting Balance $1000
    uint256 public constant USER_TARGET = 100e18;
    uint256 public constant USER_DEPOSIT = 20e18;
    uint256 public constant CHALLENGE_BASE_AMT = 1e18;
    uint256 public constant CHALLENGE_DURATION = 24; //weeks

    // Tolerance: 0.1% (accounts for rounding errors in daily compounding)
    uint256 private constant TOLERANCE_BPS = 10; // 10 basis points = 0.1%

    function setUp() public {
        deployer = new DeploySavings();
        (savings, config) = deployer.run();
        (treasury,,, usdc, usdt,,,) = config.activeNetworkConfig();
        ERC20Mock(usdc).mint(address(user), PSTARTING_USD_BAL);
        ERC20Mock(usdt).mint(address(user), PSTARTING_USD_BAL);
        console.log("Savings Address:", address(savings));
    }

    // ============================================================================
    // Helper Functions
    // ============================================================================

    /// @dev Helper to create a saving and return its ID
    function _createSaving(string memory name, uint256 target, ISavings.SavingType savingType)
        internal
        returns (bytes8 savingId)
    {
        vm.startPrank(user);
        ERC20Mock(usdc).approve(address(savings), target);
        savingId = savings.create(name, target, block.timestamp + 30 days, block.timestamp + 37 days, savingType);
        vm.stopPrank();
    }

    /// @dev Helper to deposit to a saving
    function _deposit(bytes8 savingId, uint256 amount) internal {
        vm.prank(user);
        savings.deposit(savingId, amount, usdc);
    }

    /// @dev Helper to calculate percentage difference
    /// @return bps basis points of difference (1 bps = 0.01%)
    function _percentageDifference(uint256 expected, uint256 actual) internal pure returns (uint256) {
        if (expected == 0) return 0;
        uint256 diff = expected > actual ? expected - actual : actual - expected;
        return (diff * 10000) / expected; // Convert to basis points
    }

    /// @dev Helper to verify interest calculation is within tolerance
    function _assertApproximatelyEqual(uint256 expected, uint256 actual, string memory message) internal pure {
        uint256 difference = _percentageDifference(expected, actual);
        assertLe(
            difference,
            TOLERANCE_BPS,
            string(abi.encodePacked(message, " - Difference: ", _uint2str(difference), " bps"))
        );
    }

    /// @dev Helper to convert uint to string
    function _uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - (_i / 10) * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    function testUserStartingBalances() public view {
        uint256 userUSDCbal = ERC20Mock(usdc).balanceOf(user);
        uint256 userUSDTbal = ERC20Mock(usdt).balanceOf(user);

        assertEq(userUSDCbal, PSTARTING_USD_BAL);
        assertEq(userUSDTbal, PSTARTING_USD_BAL);
    }

    function testCanCreateSavings() public {
        _createSaving("Test Saving", USER_TARGET, ISavings.SavingType.Flexible);
        ClixpesaSavings.Saving[] memory userSavings = savings.getUserSavings(user);
        require(userSavings.length > 0, "No savings created");
        assertEq(userSavings[0].name, "Test Saving");
        assertEq(userSavings[0].targetAmount, USER_TARGET);
        assertEq(uint8(userSavings[0].status), uint8(ISavings.Status.Active));
    }

    // ============================================================================
    // TIER1 Tests (6.5% APY)
    // ============================================================================

    /// @dev Test TIER1 with 1 day elapsed
    function testTier1OneDay() public {
        bytes8 savingId = _createSaving("Tier1 Test", USER_TARGET, ISavings.SavingType.Flexible);
        _deposit(savingId, USER_TARGET);

        // Advance 1 day
        vm.warp(block.timestamp + 1 days);

        // Calculate interest
        savings.applyDailyInterest(savingId);
        uint256 result = savings.getSavingsById(savingId).savedAmount;
        uint256 balance = ERC20Mock(usdc).balanceOf(treasury);
        // Expected: 100e18 * (10001725e11) / 1e18
        uint256 expected = (USER_TARGET * TIER1) / 1e18;

        assertEq(result, expected, "TIER1 1 day interest incorrect");
        console.log("Treasury Bal", balance);
    }

    function testTier1NextDayDeposit() public {
        bytes8 savingId = _createSaving("Tier1 Test", USER_TARGET, ISavings.SavingType.Flexible);
        _deposit(savingId, USER_DEPOSIT);

        // Advance 1 day
        vm.warp(block.timestamp + 1 days);
        _deposit(savingId, USER_DEPOSIT);

        uint256 result = savings.getSavingsById(savingId).savedAmount;
        uint256 expected = ((USER_DEPOSIT * TIER1) / 1e18) + USER_DEPOSIT;

        assertEq(result, expected, "TIER1 1 + Next Deposit interest incorrect");
    }

    ///@dev Test TIER1 with 365 days elapsed (1 year)
    function testTier1OneYear() public {
        bytes8 savingId = _createSaving("Tier1 1Year", USER_TARGET, ISavings.SavingType.Flexible);
        _deposit(savingId, USER_TARGET);

        // Advance 365 days
        vm.warp(block.timestamp + 365 days);

        // Calculate interest
        savings.applyDailyInterest(savingId);
        uint256 result = savings.getSavingsById(savingId).savedAmount;

        // Expected: ~1065e18 (6.5% more)
        uint256 expected = (TIER1_ANNUAL * USER_TARGET) / 1e18;

        _assertApproximatelyEqual(expected, result, "TIER1 1 year not within tolerance");
    }

    ///@dev Test TIER2 with 30 days
    function testTier2ThirtyDays() public {
        bytes8 savingId = _createSaving("Tier1 30Days", 501e18, ISavings.SavingType.Flexible);
        _deposit(savingId, 501e18);

        vm.warp(block.timestamp + 30 days);

        // Calculate interest
        savings.applyDailyInterest(savingId);
        uint256 result = savings.getSavingsById(savingId).savedAmount;

        // Expected: ~503.987e18 (30 days of 7.5% APY)
        // Calculation: 500 * (1.0001982)^30
        uint256 expected = 503987e15; // Approximately

        _assertApproximatelyEqual(expected, result, "TIER1 30 days not within tolerance");
    }

    ///@dev Test TIER2 Fixed with 30 days
    function testTier2ThirtyDaysFixed() public {
        bytes8 savingId = _createSaving("Tier2 Fixed 30Days", 501e18, ISavings.SavingType.Fixed);
        _deposit(savingId, 501e18);

        vm.warp(block.timestamp + 30 days);

        // Calculate interest
        savings.applyDailyInterest(savingId);
        uint256 result = savings.getSavingsById(savingId).savedAmount;

        // Expected: ~503.987e18 (30 days of 7.5% APY)
        // Calculation: 501 * (1.0001982)^30
        uint256 expected = 503987e15; // Approximately
        _assertApproximatelyEqual(expected, result, "TIER1 30 days not within tolerance");
    }

    /* @dev Test TIER1 with zero days (should return original amount)
    function testTier1ZeroDays() public view {
        uint256 principalAmount = 1000e18;
        uint256 lastUpdate = block.timestamp;

        uint256 result = _applyDailyInterestDirect(principalAmount, lastUpdate, TIER1, 0);

        assertEq(result, principalAmount, "TIER1 0 days should return original amount");
    }

    */
}
