// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.25;

import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract Rescuable is Initializable, ContextUpgradeable {
    using SafeERC20 for IERC20;

    /// @custom:storage-location erc7201:clixpesa.storage.Rescuable
    struct RescuableStorage {
        address rescuer;
    }

    // keccak256(abi.encode(uint256(keccak256("clixpesa.storage.Rescuable")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant RescuableStorageLocation =
        0x767596640fc4683eb0f70d625ea4da932be1f62afdbcc876a13fddbb6d072f00;

    function _getRescuableStorage() private pure returns (RescuableStorage storage $) {
        assembly {
            $.slot := RescuableStorageLocation
        }
    }

    error NotRescuer();

    event RescuerChanged(address indexed newRescuer);

    function __Rescuable_init(address _rescuer) internal onlyInitializing {
        __Rescuable_init_unchained(_rescuer);
    }

    function __Rescuable_init_unchained(address _rescuer) internal onlyInitializing {
        _updateRescuer(_rescuer);
    }

    /**
     * @notice Revert if called by any account other than the rescuer.
     */
    modifier onlyRescuer() {
        _onlyRescuer();
        _;
    }

    /**
     * @notice Returns current rescuer
     * @return Rescuer's address
     */
    function rescuer() external view returns (address) {
        RescuableStorage storage $ = _getRescuableStorage();
        return $.rescuer;
    }

    /**
     * @notice Rescue ERC20 tokens locked up in this contract.
     * @param tokenContract ERC20 token contract address
     * @param to        Recipient address
     * @param amount    Amount to withdraw
     */
    function rescueERC20(IERC20 tokenContract, address to, uint256 amount) external onlyRescuer {
        tokenContract.safeTransfer(to, amount);
    }

    /**
     * @notice Updates the blacklister address.
     * @param _newRescuer The address of the new blacklister.
     */
    function _updateRescuer(address _newRescuer) internal {
        require(_newRescuer != address(0), "Rescueable: new rescuer is the zero address");
        RescuableStorage storage $ = _getRescuableStorage();
        $.rescuer = _newRescuer;
        emit RescuerChanged(_newRescuer);
    }

    function _onlyRescuer() internal view {
        RescuableStorage storage $ = _getRescuableStorage();
        if (_msgSender() != $.rescuer) {
            revert NotRescuer();
        }
    }
}
