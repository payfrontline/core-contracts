// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title CreditManager
 * @notice Manages tokenized credit limits per user and tracks credit usage
 * @dev Enforces one active BNPL per user and credit blocks on default
 */
contract CreditManager is Ownable {
    // Custom errors
    error CreditLimitExceeded();
    error UserHasActiveBNPL();
    error UserInDefault();
    error InvalidCreditLimit();
    error Unauthorized();

    // Authorized contracts
    address public bnplCore;
    address public defaultManager;

    // Credit limit per user
    mapping(address => uint256) private _creditLimits;
    
    // Used credit per user (amount currently in active BNPL)
    mapping(address => uint256) private _usedCredit;
    
    // Default status per user
    mapping(address => bool) private _isDefaulted;
    
    // Active BNPL status per user
    mapping(address => bool) private _hasActiveBNPL;

    /**
     * @notice Constructor
     */
    constructor() Ownable(msg.sender) {}

    // Events
    event CreditLimitSet(address indexed user, uint256 limit);
    event CreditUsed(address indexed user, uint256 amount);
    event CreditRestored(address indexed user, uint256 amount);
    event UserDefaulted(address indexed user);
    event UserUnblocked(address indexed user);
    event ActiveBNPLSet(address indexed user, bool hasActive);
    event BNPLCoreSet(address indexed bnplCore);
    event DefaultManagerSet(address indexed defaultManager);

    /**
     * @notice Set the BNPLCore contract address
     * @param _bnplCore Address of BNPLCore contract
     */
    function setBNPLCore(address _bnplCore) external onlyOwner {
        bnplCore = _bnplCore;
        emit BNPLCoreSet(_bnplCore);
    }

    /**
     * @notice Set the DefaultManager contract address
     * @param _defaultManager Address of DefaultManager contract
     */
    function setDefaultManager(address _defaultManager) external onlyOwner {
        defaultManager = _defaultManager;
        emit DefaultManagerSet(_defaultManager);
    }

    /**
     * @notice Set credit limit for a user (admin only)
     * @param user Address of the user
     * @param limit Credit limit in token units
     */
    function setCreditLimit(address user, uint256 limit) external onlyOwner {
        if (limit == 0) revert InvalidCreditLimit();
        _creditLimits[user] = limit;
        emit CreditLimitSet(user, limit);
    }

    /**
     * @notice Batch set credit limits for multiple users
     * @param users Array of user addresses
     * @param limits Array of credit limits
     */
    function batchSetCreditLimits(
        address[] calldata users,
        uint256[] calldata limits
    ) external onlyOwner {
        if (users.length != limits.length) revert();
        
        for (uint256 i = 0; i < users.length; i++) {
            if (limits[i] == 0) revert InvalidCreditLimit();
            _creditLimits[users[i]] = limits[i];
            emit CreditLimitSet(users[i], limits[i]);
        }
    }

    /**
     * @notice Mark credit as used (only callable by BNPLCore)
     * @param user Address of the user
     * @param amount Amount of credit to mark as used
     */
    function useCredit(address user, uint256 amount) external {
        if (msg.sender != bnplCore) revert Unauthorized();
        
        if (_isDefaulted[user]) revert UserInDefault();
        if (_hasActiveBNPL[user]) revert UserHasActiveBNPL();
        
        uint256 available = getAvailableCredit(user);
        if (amount > available) revert CreditLimitExceeded();
        
        _usedCredit[user] += amount;
        _hasActiveBNPL[user] = true;
        
        emit CreditUsed(user, amount);
    }

    /**
     * @notice Restore credit after repayment (only callable by BNPLCore)
     * @param user Address of the user
     * @param amount Amount of credit to restore
     */
    function restoreCredit(address user, uint256 amount) external {
        if (msg.sender != bnplCore) revert Unauthorized();
        
        if (_usedCredit[user] < amount) revert();
        
        _usedCredit[user] -= amount;
        
        if (_usedCredit[user] == 0) {
            _hasActiveBNPL[user] = false;
            emit ActiveBNPLSet(user, false);
        }
        
        emit CreditRestored(user, amount);
    }

    /**
     * @notice Mark user as defaulted (only callable by DefaultManager)
     * @param user Address of the user
     */
    function markAsDefaulted(address user) external {
        if (msg.sender != defaultManager) revert Unauthorized();
        
        _isDefaulted[user] = true;
        emit UserDefaulted(user);
    }

    /**
     * @notice Unblock a user from default (admin only)
     * @param user Address of the user
     */
    function unblockUser(address user) external onlyOwner {
        _isDefaulted[user] = false;
        emit UserUnblocked(user);
    }

    /**
     * @notice Get credit limit for a user
     * @param user Address of the user
     * @return Credit limit in token units
     */
    function getCreditLimit(address user) external view returns (uint256) {
        return _creditLimits[user];
    }

    /**
     * @notice Get used credit for a user
     * @param user Address of the user
     * @return Used credit amount
     */
    function getUsedCredit(address user) external view returns (uint256) {
        return _usedCredit[user];
    }

    /**
     * @notice Get available credit for a user
     * @param user Address of the user
     * @return Available credit amount
     */
    function getAvailableCredit(address user) public view returns (uint256) {
        uint256 limit = _creditLimits[user];
        uint256 used = _usedCredit[user];
        return limit > used ? limit - used : 0;
    }

    /**
     * @notice Check if user has active BNPL
     * @param user Address of the user
     * @return True if user has active BNPL
     */
    function hasActiveBNPL(address user) external view returns (bool) {
        return _hasActiveBNPL[user];
    }

    /**
     * @notice Check if user is in default
     * @param user Address of the user
     * @return True if user is defaulted
     */
    function isDefaulted(address user) external view returns (bool) {
        return _isDefaulted[user];
    }

    /**
     * @notice Check if user can initiate BNPL
     * @param user Address of the user
     * @param amount Requested BNPL amount
     * @return True if user can initiate BNPL
     */
    function canInitiateBNPL(address user, uint256 amount) external view returns (bool) {
        if (_isDefaulted[user]) return false;
        if (_hasActiveBNPL[user]) return false;
        return getAvailableCredit(user) >= amount;
    }

    /**
     * @notice Get credit utilization percentage for a user
     * @param user Address of the user
     * @return Utilization percentage (0-10000, where 10000 = 100%)
     */
    function getCreditUtilization(address user) external view returns (uint256) {
        uint256 limit = _creditLimits[user];
        if (limit == 0) return 0;
        uint256 used = _usedCredit[user];
        return (used * 10000) / limit;
    }
}
