// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./CreditManager.sol";
import "./LiquidityPool.sol";
import "./DefaultManager.sol";
import "./HCSLogger.sol";
import "./interfaces/IERC20HTS.sol";

/**
 * @title BNPLCore
 * @notice Main orchestrator contract for BNPL transactions
 * @dev Handles BNPL creation, validation, merchant payouts, and repayments
 */
contract BNPLCore is Ownable, ReentrancyGuard {
    // Custom errors
    error InvalidAmount();
    error InvalidMerchant();
    error InvalidUser();
    error InsufficientCredit();
    error UserInDefault();
    error UserHasActiveBNPL();
    error KYCNotPassed();
    error InsufficientLiquidity();
    error BNPLNotFound();
    error BNPLAlreadyRepaid();
    error BNPLNotDue();
    error RepaymentAmountMismatch();
    error Unauthorized();

    // Contract references
    CreditManager public creditManager;
    LiquidityPool public liquidityPool;
    DefaultManager public defaultManager;
    HCSLogger public hcsLogger;
    IERC20HTS public paymentToken;

    // BNPL configuration
    uint256 public repaymentWindowDays = 14; // Default 14 days
    uint256 public protocolFeeBps = 50; // 0.5% (50 basis points)

    // BNPL state
    struct BNPL {
        address user;
        address merchant;
        uint256 amount;
        uint256 dueDate;
        uint256 createdAt;
        bool isRepaid;
        bool isDefaulted;
    }

    // Mapping from BNPL ID to BNPL struct
    mapping(uint256 => BNPL) public bnpls;
    
    // Mapping from user to active BNPL ID
    mapping(address => uint256) public activeBNPLId;
    
    // BNPL counter
    uint256 public bnplCounter;

    // Events
    event BNPLCreated(
        address indexed user,
        address indexed merchant,
        uint256 indexed bnplId,
        uint256 amount,
        uint256 dueDate
    );
    event BNPLRepaid(
        address indexed user,
        uint256 indexed bnplId,
        uint256 amount,
        uint256 repaidAt
    );
    event BNPLDefaulted(
        address indexed user,
        uint256 indexed bnplId,
        uint256 amount
    );
    event RepaymentWindowSet(uint256 days_);
    event ProtocolFeeSet(uint256 bps);
    event CreditManagerSet(address indexed creditManager);
    event LiquidityPoolSet(address indexed liquidityPool);
    event DefaultManagerSet(address indexed defaultManager);
    event HCSLoggerSet(address indexed logger);
    event PaymentTokenSet(address indexed token);

    /**
     * @notice Constructor
     * @param _creditManager Address of CreditManager contract
     * @param _liquidityPool Address of LiquidityPool contract
     * @param _defaultManager Address of DefaultManager contract
     * @param _hcsLogger Address of HCSLogger contract
     * @param _paymentToken Address of payment token
     */
    constructor(
        address _creditManager,
        address _liquidityPool,
        address _defaultManager,
        address _hcsLogger,
        address _paymentToken
    ) Ownable(msg.sender) {
        if (
            _creditManager == address(0) ||
            _liquidityPool == address(0) ||
            _defaultManager == address(0) ||
            _hcsLogger == address(0) ||
            _paymentToken == address(0)
        ) {
            revert();
        }

        creditManager = CreditManager(_creditManager);
        liquidityPool = LiquidityPool(_liquidityPool);
        defaultManager = DefaultManager(_defaultManager);
        hcsLogger = HCSLogger(_hcsLogger);
        paymentToken = IERC20HTS(_paymentToken);
    }

    /**
     * @notice Initialize contract references in other contracts
     * @dev Should be called after deployment to set up cross-contract references
     */
    function initializeContracts() external onlyOwner {
        creditManager.setBNPLCore(address(this));
        liquidityPool.setBNPLCore(address(this));
        defaultManager.setBNPLCore(address(this));
    }

    /**
     * @notice Set repayment window in days
     * @param _days Number of days for repayment window
     */
    function setRepaymentWindow(uint256 _days) external onlyOwner {
        if (_days == 0) revert InvalidAmount();
        repaymentWindowDays = _days;
        emit RepaymentWindowSet(_days);
    }

    /**
     * @notice Set protocol fee in basis points
     * @param _bps Fee in basis points (10000 = 100%)
     */
    function setProtocolFee(uint256 _bps) external onlyOwner {
        if (_bps > 10000) revert(); // Max 100%
        protocolFeeBps = _bps;
        emit ProtocolFeeSet(_bps);
    }

    /**
     * @notice Create a new BNPL transaction
     * @param user Address of the user
     * @param merchant Address of the merchant
     * @param amount BNPL amount
     * @return bnplId The ID of the created BNPL
     */
    function createBNPL(
        address user,
        address merchant,
        uint256 amount
    ) external nonReentrant returns (uint256) {
        // Validation
        if (amount == 0) revert InvalidAmount();
        if (user == address(0)) revert InvalidUser();
        if (merchant == address(0)) revert InvalidMerchant();

        // Check user eligibility
        if (creditManager.isDefaulted(user)) revert UserInDefault();
        if (creditManager.hasActiveBNPL(user)) revert UserHasActiveBNPL();

        // Check KYC status (if token supports it)
        try paymentToken.isKycPassed(user) returns (bool kycPassed) {
            if (!kycPassed) revert KYCNotPassed();
        } catch {
            // If token doesn't support KYC check, continue
            // In production, you may want to enforce this differently
        }

        // Check credit availability
        if (!creditManager.canInitiateBNPL(user, amount)) {
            revert InsufficientCredit();
        }

        // Check liquidity availability
        uint256 availableLiquidity = liquidityPool.getAvailableLiquidity();
        if (availableLiquidity < amount) revert InsufficientLiquidity();

        // Generate BNPL ID
        uint256 bnplId = ++bnplCounter;

        // Calculate due date
        uint256 dueDate = block.timestamp + (repaymentWindowDays * 1 days);

        // Create BNPL record
        bnpls[bnplId] = BNPL({
            user: user,
            merchant: merchant,
            amount: amount,
            dueDate: dueDate,
            createdAt: block.timestamp,
            isRepaid: false,
            isDefaulted: false
        });

        // Mark user as having active BNPL
        activeBNPLId[user] = bnplId;

        // Mark credit as used
        creditManager.useCredit(user, amount);

        // Calculate protocol fee
        uint256 fee = (amount * protocolFeeBps) / 10000;
        uint256 merchantAmount = amount - fee;

        // Settle merchant payment instantly
        liquidityPool.settleMerchant(merchant, merchantAmount, bnplId);

        // Collect protocol fee
        if (fee > 0) {
            liquidityPool.collectFees(fee);
        }

        // Log to HCS
        hcsLogger.logBNPLCreation(user, merchant, bnplId, amount, dueDate);

        emit BNPLCreated(user, merchant, bnplId, amount, dueDate);

        return bnplId;
    }

    /**
     * @notice Repay a BNPL loan
     * @param bnplId BNPL transaction ID
     */
    function repayBNPL(uint256 bnplId) external nonReentrant {
        BNPL storage bnpl = bnpls[bnplId];
        
        if (bnpl.user == address(0)) revert BNPLNotFound();
        if (bnpl.isRepaid) revert BNPLAlreadyRepaid();

        // User must repay their own BNPL
        if (msg.sender != bnpl.user) revert Unauthorized();

        // Transfer repayment from user to liquidity pool
        liquidityPool.receiveRepayment(bnpl.user, bnpl.amount, bnplId);

        // Mark as repaid
        bnpl.isRepaid = true;

        // Restore user credit
        creditManager.restoreCredit(bnpl.user, bnpl.amount);

        // Clear active BNPL
        delete activeBNPLId[bnpl.user];

        // Log to HCS
        hcsLogger.logRepayment(
            bnpl.user,
            bnpl.merchant,
            bnplId,
            bnpl.amount,
            true
        );

        emit BNPLRepaid(bnpl.user, bnplId, bnpl.amount, block.timestamp);
    }

    /**
     * @notice Mark a BNPL as defaulted (called by DefaultManager)
     * @param user Address of the user
     * @param bnplId BNPL transaction ID
     */
    function markBNPLAsDefaulted(address user, uint256 bnplId) external {
        if (msg.sender != address(defaultManager)) revert Unauthorized();

        BNPL storage bnpl = bnpls[bnplId];
        if (bnpl.user != user) revert();
        if (bnpl.isRepaid) revert();
        
        bnpl.isDefaulted = true;

        emit BNPLDefaulted(user, bnplId, bnpl.amount);
    }

    /**
     * @notice Get BNPL details
     * @param bnplId BNPL transaction ID
     * @return exists Whether BNPL exists
     * @return dueDate Due date timestamp
     * @return amount BNPL amount
     * @return isRepaid Whether BNPL is repaid
     */
    function getBNPLDetails(uint256 bnplId) external view returns (
        bool exists,
        uint256 dueDate,
        uint256 amount,
        bool isRepaid
    ) {
        BNPL memory bnpl = bnpls[bnplId];
        exists = bnpl.user != address(0);
        if (exists) {
            dueDate = bnpl.dueDate;
            amount = bnpl.amount;
            isRepaid = bnpl.isRepaid;
        }
    }

    /**
     * @notice Get full BNPL information
     * @param bnplId BNPL transaction ID
     * @return bnpl BNPL struct
     */
    function getBNPL(uint256 bnplId) external view returns (BNPL memory) {
        return bnpls[bnplId];
    }

    /**
     * @notice Get active BNPL ID for a user
     * @param user Address of the user
     * @return bnplId Active BNPL ID (0 if none)
     */
    function getActiveBNPLId(address user) external view returns (uint256) {
        return activeBNPLId[user];
    }

    /**
     * @notice Check if user can create BNPL
     * @param user Address of the user
     * @param amount Requested amount
     * @return True if user can create BNPL
     */
    function canCreateBNPL(address user, uint256 amount) external view returns (bool) {
        if (creditManager.isDefaulted(user)) return false;
        if (creditManager.hasActiveBNPL(user)) return false;
        if (!creditManager.canInitiateBNPL(user, amount)) return false;
        
        uint256 availableLiquidity = liquidityPool.getAvailableLiquidity();
        if (availableLiquidity < amount) return false;

        return true;
    }
}
