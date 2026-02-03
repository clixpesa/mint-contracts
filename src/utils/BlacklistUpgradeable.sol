// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.25;

import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

abstract contract BlacklistUpgradeable is Initializable, ContextUpgradeable {
    /// @custom:storage-location erc7201:clixpesa.storage.Blacklistable
    struct BlacklistStorage {
        address blacklister;
        mapping(address account => bool) blacklisted;
    }

    // keccak256(abi.encode(uint256(keccak256("clixpesa.storage.Blacklistable")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant BlacklistStorageLocation =
        0x7e4cd74db0c087d07e75be51a7fbcb024eb70788125237c9415c615019ab7400;

    function _getBlacklistStorage() private pure returns (BlacklistStorage storage $) {
        assembly {
            $.slot := BlacklistStorageLocation
        }
    }

    error AccountBlacklisted(address account);
    error NotBlacklister();

    event Blacklisted(address indexed account);
    event UnBlacklisted(address indexed account);
    event BlacklisterChanged(address indexed newBlacklister);

    function __Blacklist_init(address blacklister) internal onlyInitializing {
        __Blacklist_init_unchained(blacklister);
    }

    function __Blacklist_init_unchained(address blacklister) internal onlyInitializing {
        _updateBlacklister(blacklister);
    }

    /**
     * @dev Throws if called by any account other than the blacklister.
     */
    modifier onlyBlacklister() {
        _onlyBlacklister();
        _;
    }

    /**
     * @dev Throws if argument account is blacklisted.
     * @param _account The address to check.
     */
    modifier notBlacklisted(address _account) {
        _notBlacklisted(_account);
        _;
    }

    /**
     * @notice Checks if account is blacklisted.
     * @param _account The address to check.
     * @return True if the account is blacklisted, false if the account is not blacklisted.
     */
    function isBlacklisted(address _account) external view returns (bool) {
        BlacklistStorage storage $ = _getBlacklistStorage();
        return $.blacklisted[_account];
    }

    /**
     * @notice Adds account to blacklist.
     * @param _account The address to blacklist.
     */
    function _blacklist(address _account) internal virtual onlyBlacklister returns (bool) {
        BlacklistStorage storage $ = _getBlacklistStorage();
        bool blacklisted = $.blacklisted[_account];
        if (!blacklisted) {
            $.blacklisted[_account] = true;
            emit Blacklisted(_account);
        }
        return !blacklisted;
    }

    /**
     * @notice Removes account from blacklist.
     * @param _account The address to remove from the blacklist.
     */
    function _unBlacklist(address _account) internal virtual onlyBlacklister returns (bool) {
        BlacklistStorage storage $ = _getBlacklistStorage();
        bool blacklisted = $.blacklisted[_account];
        if (blacklisted) {
            $.blacklisted[_account] = false;
            emit UnBlacklisted(_account);
        }
        return blacklisted;
    }

    /**
     * @notice Updates the blacklister address.
     * @param _newBlacklister The address of the new blacklister.
     */
    function _updateBlacklister(address _newBlacklister) internal {
        require(_newBlacklister != address(0), "Blacklistable: new blacklister is the zero address");
        BlacklistStorage storage $ = _getBlacklistStorage();
        $.blacklister = _newBlacklister;
        emit BlacklisterChanged(_newBlacklister);
    }

    function _notBlacklisted(address _account) internal view {
        BlacklistStorage storage $ = _getBlacklistStorage();
        bool blacklisted = $.blacklisted[_account];
        if (blacklisted) {
            revert AccountBlacklisted(_account);
        }
    }

    function _onlyBlacklister() internal view {
        BlacklistStorage storage $ = _getBlacklistStorage();
        if (_msgSender() != $.blacklister) {
            revert NotBlacklister();
        }
    }
}
