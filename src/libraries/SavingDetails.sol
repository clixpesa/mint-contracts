// SPDX-License-Identifier: Apache-2.0

pragma solidity >=0.8.25;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {DateTimeLib} from "@solady/contracts/utils/DateTimeLib.sol";
import {ISavings} from "../interfaces/ISavings.sol";

/// @notice Library to generate saving details.
library SavingDetails {
    struct Dates {
        uint256 startDate;
        uint256 endDate;
        uint256 payoutDate;
        uint256 duration; //in months
    }
    /// @notice Constants for time calculations
    uint256 private constant SECONDS_PER_DAY = 86400;
    uint256 private constant SECONDS_PER_WEEK = 604800;

    /// @notice Calculate start date, payout date, and end date for a monthly recurring deposit plan
    /// @param durationMonths Number of months (6, 12, 18 or 24)
    /// @param createdDate The Unix timestamp when the plan is created
    /// @return dates Struct containing startDate, payoutDate, endDate, and duration
    function getMonthlyDates(uint256 durationMonths, uint256 createdDate) internal pure returns (Dates memory dates) {
        // Extract day, month, year from Unix timestamp
        (uint256 createdYear, uint256 createdMonth, uint256 createdDay) = DateTimeLib.timestampToDate(createdDate);

        uint256 startMonth = createdMonth;
        uint256 startYear = createdYear;

        // If created between 1-24th, deposits start this month (25th onwards)
        // If created between 25th-31st, deposits start next month
        if (createdDay >= 25) {
            startMonth += 1;
            if (startMonth > 12) {
                startMonth = 1;
                startYear += 1;
            }
        }

        // Start date is the 25th of the determined start month
        uint256 startDate = DateTimeLib.dateToTimestamp(startYear, startMonth, 25);

        // Payout date is 28th of the month after duration ends
        uint256 payoutMonth = startMonth + durationMonths;
        uint256 payoutYear = startYear;
        while (payoutMonth > 12) {
            payoutMonth -= 12;
            payoutYear += 1;
        }
        uint256 payoutDate = DateTimeLib.dateToTimestamp(payoutYear, payoutMonth, 28);

        // End date is the 5th of the last month (one month after start + duration)
        uint256 endMonth = startMonth + durationMonths;
        uint256 endYear = startYear;
        while (endMonth > 12) {
            endMonth -= 12;
            endYear += 1;
        }
        uint256 endDate = DateTimeLib.dateToTimestamp(endYear, endMonth, 5);

        dates = Dates({startDate: startDate, payoutDate: payoutDate, endDate: endDate, duration: durationMonths});
    }

    /// @notice Calculate start date, payout date, and end date for a weekly recurring deposit plan
    /// @param durationWeeks Number of weeks (e.g., 4, 8, 12, etc.)
    /// @param createdDate The Unix timestamp when the plan is created
    /// @return dates Struct containing startDate, payoutDate, endDate, and duration (in months)
    function getWeeklyDates(uint256 durationWeeks, uint256 createdDate) internal pure returns (Dates memory dates) {
        // Start date is the same day the plan is created
        uint256 startDate = createdDate;

        // First week deadline (next Sunday)
        uint256 firstWeekDeadline = get1stDeadline(startDate);

        // Calculate the final end date: weeks after first week ends
        uint256 endDate = firstWeekDeadline + (durationWeeks * SECONDS_PER_WEEK);

        // Payout date is Friday of the week of the end date
        uint256 dayOfWeekEnd = DateTimeLib.weekday(endDate);

        uint256 daysUntilFriday;
        if (dayOfWeekEnd == 5) {
            // If endDate is already Friday, payout is the same day
            daysUntilFriday = 0;
        } else if (dayOfWeekEnd < 5) {
            // If it's Mon-Thu, Friday is ahead
            daysUntilFriday = 5 - dayOfWeekEnd;
        } else {
            // If it's Sat or Sun, Friday of next week
            daysUntilFriday = 12 - dayOfWeekEnd;
        }

        uint256 payoutDate = endDate + (daysUntilFriday * SECONDS_PER_DAY);

        // Duration in months (approximate)
        uint256 durationMonths = durationWeeks / 4;

        dates = Dates({startDate: startDate, payoutDate: payoutDate, endDate: endDate, duration: durationMonths});
    }

    /// @notice Get the first deadline for a weekly challenge.
    function get1stDeadline(uint256 startDate) internal pure returns (uint256 firstDeadline) {
        // Find the day of week (0 = Thursday, 1 = Friday, ..., 6 = Wednesday in Unix epoch)
        // We need to adjust for Monday = 1, ..., Sunday = 7
        uint256 dayOfWeek = DateTimeLib.weekday(startDate);

        // Calculate days until next Sunday
        // If today is Sunday (7), next Sunday is 7 days away
        // Otherwise, it's (7 - dayOfWeek) days away
        uint256 daysUntilSunday = (7 - dayOfWeek);
        if (daysUntilSunday == 0) {
            daysUntilSunday = 7;
        }

        // First week deadline (next Sunday)
        firstDeadline = startDate + (daysUntilSunday * SECONDS_PER_DAY);
    }

    /// @notice Get weeks installment amount for a weekly challenge.
    function getInstallment(uint256 weekNo, uint256 baseAmount, uint256 duration, ISavings.ChallengePref preference)
        internal
        pure
        returns (uint256 amount)
    {
        if (weekNo == 0) revert ISavings.MustMoreBeThanZero();
        if (weekNo > duration) revert ISavings.UnsupportedDuration();
        if (preference == ISavings.ChallengePref.Even) {
            amount = baseAmount;
        } else if (preference == ISavings.ChallengePref.Low) {
            amount = baseAmount * weekNo;
        } else if (preference == ISavings.ChallengePref.High) {
            amount = (baseAmount * duration) - (baseAmount * (weekNo - 1));
        }
    }

    /// @notice Get base weekly challenge base amount.
    /// @param targetAmount The Unix timestamp when the plan is created
    /// @param duration Number of weeks (e.g., 16, 24, 48 etc.)
    /// @param preference Challenge preference
    function getBaseAmount(uint256 targetAmount, uint256 duration, ISavings.ChallengePref preference)
        internal
        pure
        returns (uint256 baseAmount)
    {
        if (targetAmount <= 0) revert ISavings.MustMoreBeThanZero();
        if ((duration % 4) != 0) revert ISavings.UnsupportedDuration();
        if (preference == ISavings.ChallengePref.Even) {
            (, baseAmount) = Math.tryDiv(targetAmount, duration);
        } else {
            uint256 sumOfWeeks = (duration * (duration + 1)) / 2;
            (, baseAmount) = Math.tryDiv(targetAmount, sumOfWeeks);
        }
    }
}
