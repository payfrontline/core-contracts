// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title HCSLogger
 * @notice Lightweight event emission contract for Hedera Consensus Service mirroring
 * @dev Pure event contract - no storage, no state changes
 */
contract HCSLogger {
    // Repayment events
    event RepaymentLogged(
        address indexed user,
        address indexed merchant,
        uint256 indexed bnplId,
        uint256 amount,
        uint256 timestamp,
        bool successful
    );

    // Default events
    event DefaultLogged(
        address indexed user,
        uint256 indexed bnplId,
        uint256 overdueAmount,
        uint256 daysOverdue,
        uint256 timestamp
    );

    // BNPL creation events
    event BNPLCreationLogged(
        address indexed user,
        address indexed merchant,
        uint256 indexed bnplId,
        uint256 amount,
        uint256 dueDate,
        uint256 timestamp
    );

    // Dispute/audit events
    event DisputeLogged(
        address indexed user,
        address indexed merchant,
        uint256 indexed bnplId,
        string reason,
        uint256 timestamp
    );

    /**
     * @notice Log a repayment event for HCS mirroring
     */
    function logRepayment(
        address user,
        address merchant,
        uint256 bnplId,
        uint256 amount,
        bool successful
    ) external {
        emit RepaymentLogged(
            user,
            merchant,
            bnplId,
            amount,
            block.timestamp,
            successful
        );
    }

    /**
     * @notice Log a default event for HCS mirroring
     */
    function logDefault(
        address user,
        uint256 bnplId,
        uint256 overdueAmount,
        uint256 daysOverdue
    ) external {
        emit DefaultLogged(
            user,
            bnplId,
            overdueAmount,
            daysOverdue,
            block.timestamp
        );
    }

    /**
     * @notice Log a BNPL creation event for HCS mirroring
     */
    function logBNPLCreation(
        address user,
        address merchant,
        uint256 bnplId,
        uint256 amount,
        uint256 dueDate
    ) external {
        emit BNPLCreationLogged(
            user,
            merchant,
            bnplId,
            amount,
            dueDate,
            block.timestamp
        );
    }

    /**
     * @notice Log a dispute event for HCS mirroring
     */
    function logDispute(
        address user,
        address merchant,
        uint256 bnplId,
        string memory reason
    ) external {
        emit DisputeLogged(
            user,
            merchant,
            bnplId,
            reason,
            block.timestamp
        );
    }
}
