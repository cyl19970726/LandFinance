// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IGovernor.sol";

/**
 * @dev Extension of the {IGovernor} for timelock supporting modules.
 *
 * _Available since v4.3._
 */
abstract contract IGovernorTimelock is IGovernor {
    // @dev How long to wait for a proposal after the voting ends if proposal status is succeed
    function timeDelayedExecute() public view virtual returns(uint256);

}
