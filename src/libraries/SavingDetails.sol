// SPDX-License-Identifier: Apache-2.0

pragma solidity >=0.8.25;

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
        (uint256 createdYear, uint256 createdMonth, uint256 createdDay) = _timestampToDate(createdDate);

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
        uint256 startDate = _dateToTimestamp(startYear, startMonth, 25);

        // Payout date is 28th of the month after duration ends
        uint256 payoutMonth = startMonth + durationMonths;
        uint256 payoutYear = startYear;
        while (payoutMonth > 12) {
            payoutMonth -= 12;
            payoutYear += 1;
        }
        uint256 payoutDate = _dateToTimestamp(payoutYear, payoutMonth, 28);

        // End date is the 5th of the last month (one month after start + duration)
        uint256 endMonth = startMonth + durationMonths - 1;
        uint256 endYear = startYear;
        while (endMonth > 12) {
            endMonth -= 12;
            endYear += 1;
        }
        uint256 endDate = _dateToTimestamp(endYear, endMonth, 5);

        dates = Dates({startDate: startDate, payoutDate: payoutDate, endDate: endDate, duration: durationMonths});
    }

    /// @notice Calculate start date, payout date, and end date for a weekly recurring deposit plan
    /// @param durationWeeks Number of weeks (e.g., 4, 8, 12, etc.)
    /// @param createdDate The Unix timestamp when the plan is created
    /// @return dates Struct containing startDate, payoutDate, endDate, and duration (in months)
    function getWeeklyDates(uint256 durationWeeks, uint256 createdDate) internal pure returns (Dates memory dates) {
        // Start date is the same day the plan is created
        uint256 startDate = createdDate;

        // Find the day of week (0 = Thursday, 1 = Friday, ..., 6 = Wednesday in Unix epoch)
        // We need to adjust for Sunday = 0, Monday = 1, ..., Saturday = 6
        uint256 dayOfWeek = _getDayOfWeek(createdDate);

        // Calculate days until next Sunday
        // If today is Sunday (0), next Sunday is 7 days away
        // Otherwise, it's (7 - dayOfWeek) days away
        uint256 daysUntilSunday = (7 - dayOfWeek) % 7;
        if (daysUntilSunday == 0) {
            daysUntilSunday = 7;
        }

        // First week end date (next Sunday)
        uint256 firstWeekEndDate = createdDate + (daysUntilSunday * SECONDS_PER_DAY);

        // Calculate the final end date: (durationWeeks - 1) weeks after first week ends
        uint256 endDate = firstWeekEndDate + ((durationWeeks - 1) * SECONDS_PER_WEEK);

        // Payout date is Friday of the week of the end date
        uint256 dayOfWeekEnd = _getDayOfWeek(endDate);

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

    // ============ Internal Helper Functions ============

    /// @notice Convert Unix timestamp to (year, month, day)
    /// @param timestamp Unix timestamp (seconds since epoch)
    /// @return year The year
    /// @return month The month (1-12)
    /// @return day The day of month (1-31)
    function _timestampToDate(uint256 timestamp) internal pure returns (uint256 year, uint256 month, uint256 day) {
        // Based on Zeller's congruence algorithm
        uint256 secondsPerDay = 86400;
        uint256 daysCount = timestamp / secondsPerDay;

        // Unix epoch started on Thursday, January 1, 1970
        // We'll use a simplified calculation
        uint256 z = daysCount + 719468; // Adjust epoch offset
        uint256 era = z / 146097;
        uint256 doe = z - (era * 146097);
        uint256 yoe = (doe - doe / 1461 + doe / 36524 - doe / 146096) / 365;

        year = yoe + era * 400 + 1970;
        uint256 doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        month = (5 * doy + 308) / 153;
        day = doy - (153 * month + 2) / 5 + 1;

        if (month > 12) {
            month -= 12;
            year += 1;
        }
    }

    /// @notice Convert (year, month, day) to Unix timestamp (at 00:00:00 UTC)
    /// @param year The year
    /// @param month The month (1-12)
    /// @param day The day of month (1-31)
    /// @return timestamp Unix timestamp at midnight UTC
    function _dateToTimestamp(uint256 year, uint256 month, uint256 day) internal pure returns (uint256 timestamp) {
        // Algorithm to convert Gregorian date to Unix timestamp
        uint256 a = (14 - month) / 12;
        year = year - a;
        month = month + 12 * a - 2;
        // Days from epoch (Jan 1, 1970)
        uint256 daysFromEpoch = (year - 1970) * 365 + (year - 1969) / 4 - (year - 1901) / 100 + (year - 1601) / 400
            + (153 * month + 2) / 5 + day - 1;

        timestamp = daysFromEpoch * 86400;
    }

    /// @notice Get day of week from Unix timestamp
    /// @param timestamp Unix timestamp
    /// @return dayOfWeek 0 = Sunday, 1 = Monday, ..., 6 = Saturday
    function _getDayOfWeek(uint256 timestamp) internal pure returns (uint256 dayOfWeek) {
        // Unix epoch (Jan 1, 1970) was a Thursday
        // Add 4 to shift so Sunday = 0
        dayOfWeek = ((timestamp / 86400 + 4) % 7);
    }
}
