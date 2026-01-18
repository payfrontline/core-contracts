// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./CreditManager.sol";
import "./interfaces/IERC20HTS.sol";
import "./HCSLogger.sol";

/**
 * @title DefaultManager
 * @notice Detects overdue BNPLs, marks users as defaulted, and triggers token freezes
 * @dev Callable by admin or keeper bot
 */
contract DefaultManager is Ownable {
    // Custom errors
    error Unauthorized();
    error BNPLNotFound();
    error BNPLNotOverdue();
    error AlreadyDefaulted();
    error InvalidBNPLCore();

    // Authorized contracts
    address public bnplCore;
    CreditManager public creditManager;
    IERC20HTS public paymentToken;
    HCSLogger public hcsLogger;

    // Default detection parameters
    uint256 public gracePeriodDays = 0; // Days after due date before default

    // Events
    event BNPLCoreSet(address indexed bnplCore);
    event CreditManagerSet(address indexed creditManager);
    event PaymentTokenSet(address indexed token);
    event HCSLoggerSet(address indexed logger);
    event GracePeriodSet(uint256 days_);
    event DefaultDetected(address indexed user, uint256 indexed bnplId, uint256 daysOverdue);
    event TokenFrozen(address indexed user);

    /**
     * @notice Constructor
     * @param _creditManager Address of CreditManager contract
     * @param _paymentToken Address of payment token
     * @param _hcsLogger Address of HCSLogger contract
     */
    constructor(
        address _creditManager,
        address _paymentToken,
        address _hcsLogger
    ) Ownable(msg.sender) {
        if (_creditManager == address(0) || _paymentToken == address(0) || _hcsLogger == address(0)) {
            revert();
        }
        creditManager = CreditManager(_creditManager);
        paymentToken = IERC20HTS(_paymentToken);
        hcsLogger = HCSLogger(_hcsLogger);
    }

    /**
     * @notice Set the BNPLCore contract address
     * @param _bnplCore Address of BNPLCore contract
     */
    function setBNPLCore(address _bnplCore) external onlyOwner {
        if (_bnplCore == address(0)) revert InvalidBNPLCore();
        bnplCore = _bnplCore;
        emit BNPLCoreSet(_bnplCore);
    }

    /**
     * @notice Set grace period for default detection
     * @param _gracePeriodDays Number of days after due date before default
     */
    function setGracePeriod(uint256 _gracePeriodDays) external onlyOwner {
        gracePeriodDays = _gracePeriodDays;
        emit GracePeriodSet(_gracePeriodDays);
    }

    /**
     * @notice Check if a BNPL is overdue and process default if needed
     * @param user Address of the user
     * @param bnplId BNPL transaction ID
     * @return True if default was processed
     */
    function checkAndProcessDefault(
        address user,
        uint256 bnplId
    ) external returns (bool) {
        // Can be called by admin or keeper bot
        if (msg.sender != owner() && msg.sender != bnplCore) {
            revert Unauthorized();
        }

        // Get BNPL details from BNPLCore (interface call)
        (bool exists, uint256 dueDate, uint256 amount, bool isRepaid) = 
            IBNPLCore(bnplCore).getBNPLDetails(bnplId);

        if (!exists) revert BNPLNotFound();
        if (isRepaid) return false;

        // Check if overdue
        uint256 currentTime = block.timestamp;
        if (currentTime < dueDate + (gracePeriodDays * 1 days)) {
            revert BNPLNotOverdue();
        }

        // Check if already defaulted
        if (creditManager.isDefaulted(user)) {
            return false;
        }

        // Calculate days overdue
        uint256 daysOverdue = (currentTime - dueDate) / 1 days;

        // Mark user as defaulted in CreditManager
        creditManager.markAsDefaulted(user);

        // Freeze user's token account
        try paymentToken.freeze(user) {
            emit TokenFrozen(user);
        } catch {
            // Token freeze may fail if not supported or already frozen
            // Continue with default marking
        }

        // Log to HCS
        hcsLogger.logDefault(user, bnplId, amount, daysOverdue);

        emit DefaultDetected(user, bnplId, daysOverdue);

        return true;
    }

    /**
     * @notice Batch check and process defaults for multiple users
     * @param users Array of user addresses
     * @param bnplIds Array of BNPL IDs
     * @return Number of defaults processed
     */
    function batchCheckDefaults(
        address[] calldata users,
        uint256[] calldata bnplIds
    ) external returns (uint256) {
        if (users.length != bnplIds.length) revert();
        
        uint256 processed = 0;
        for (uint256 i = 0; i < users.length; i++) {
            // Inline the default check logic to avoid external call overhead
            address user = users[i];
            uint256 bnplId = bnplIds[i];
            
            // Get BNPL details from BNPLCore
            (bool exists, uint256 dueDate, uint256 amount, bool isRepaid) = 
                IBNPLCore(bnplCore).getBNPLDetails(bnplId);

            if (!exists || isRepaid) continue;

            // Check if overdue
            uint256 currentTime = block.timestamp;
            if (currentTime < dueDate + (gracePeriodDays * 1 days)) continue;

            // Check if already defaulted
            if (creditManager.isDefaulted(user)) continue;

            // Process default
            uint256 daysOverdue = (currentTime - dueDate) / 1 days;
            creditManager.markAsDefaulted(user);

            // Freeze user's token account
            try paymentToken.freeze(user) {
                emit TokenFrozen(user);
            } catch {
                // Continue if freeze fails
            }

            // Log to HCS
            hcsLogger.logDefault(user, bnplId, amount, daysOverdue);
            emit DefaultDetected(user, bnplId, daysOverdue);
            
            // Notify BNPLCore
            try IBNPLCore(bnplCore).markBNPLAsDefaulted(user, bnplId) {
            } catch {
                // Continue if notification fails
            }

            processed++;
        }
        return processed;
    }
}

/**
 * @title IBNPLCore
 * @notice Interface for BNPLCore to query BNPL details and mark defaults
 */
interface IBNPLCore {
    function getBNPLDetails(uint256 bnplId) external view returns (
        bool exists,
        uint256 dueDate,
        uint256 amount,
        bool isRepaid
    );
    function markBNPLAsDefaulted(address user, uint256 bnplId) external;
}
