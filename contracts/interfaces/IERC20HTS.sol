// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IERC20HTS
 * @notice HTS-compatible ERC20 interface with freeze and KYC capabilities
 * @dev Assumes token supports Hedera Token Service features
 */
interface IERC20HTS {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    
    // HTS-specific functions (abstracted)
    function freeze(address account) external;
    function unfreeze(address account) external;
    function isFrozen(address account) external view returns (bool);
    function isKycPassed(address account) external view returns (bool);
}
