// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {SavingDetails} from "../src/libraries/SavingDetails.sol";
import {DateTimeLib} from "@solady/contracts/utils/DateTimeLib.sol";
import {ISavings} from "../src/interfaces/ISavings.sol";

contract SavingDetailsTest is Test {
    function testGetMonthlyDates() public pure {
        uint256 durationMonths = 12;
        uint256 createdDate = 1770797528;
        SavingDetails.Dates memory dates = SavingDetails.getMonthlyDates(durationMonths, createdDate);
        assertEq(dates.startDate, 1771977600, "Wrong start date");
        assertEq(dates.endDate, 1801785600, "Wrong end date");
        assertEq(dates.payoutDate, 1803772800, "Wrong payout date");
        assertEq(dates.duration, durationMonths, "False duration");
    }

    function testGetWeeklyDates() public pure {
        uint256 durationWeeks = 36;
        uint256 createdDate = 1770797528;
        SavingDetails.Dates memory dates = SavingDetails.getWeeklyDates(durationWeeks, createdDate);
        uint256 expectedEndDate = DateTimeLib.addDays(1771143128, 252);
        assertEq(dates.startDate, createdDate, "Wrong start date");
        assertEq(dates.endDate, expectedEndDate, "Wrong end date");
        assertEq(dates.payoutDate, 1793347928, "Wrong payout date");
        assertEq(dates.duration, durationWeeks / 4, "False duration");
    }

    function testGetBaseAmount() public pure {
        uint256 duration = 0;
        uint256 targetAmount = 1000000000000000000000;
        uint256 baseAmount = SavingDetails.getBaseAmount(targetAmount, duration, ISavings.ChallengePref.Low);
        console.log(baseAmount);
    }

    function testGetInstallmentLow() public pure {
        uint256 duration = 36;
        uint256 targetAmount = 1000000000000000000000;
        ISavings.ChallengePref preference = ISavings.ChallengePref.Low;
        uint256 baseAmount = SavingDetails.getBaseAmount(targetAmount, duration, preference);
        uint256[] memory breakdown = new uint256[](duration + 1);
        for (uint256 i = 1; i <= duration; i++) {
            breakdown[i] = baseAmount * i;
        }

        for (uint256 i = 1; i <= duration; i++) {
            uint256 installment = SavingDetails.getInstallment(i, baseAmount, duration, preference);
            assertEq(installment, breakdown[i], "Wrong Installment");
        }
    }

    function testGetInstallmentHigh() public pure {
        uint256 duration = 36;
        uint256 targetAmount = 1000000000000000000000;
        ISavings.ChallengePref preference = ISavings.ChallengePref.High;
        uint256 baseAmount = SavingDetails.getBaseAmount(targetAmount, duration, preference);
        uint256[] memory breakdown = new uint256[](duration + 1);
        for (uint256 i = 1; i <= duration; i++) {
            breakdown[i] = baseAmount * (duration - i + 1);
        }

        for (uint256 i = 1; i <= duration; i++) {
            uint256 installment = SavingDetails.getInstallment(i, baseAmount, duration, preference);
            assertEq(installment, breakdown[i], "Wrong Installment");
        }
    }
}
