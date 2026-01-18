// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IERC20HTS.sol";

/**
 * @title LiquidityPool
 * @notice Manages protocol liquidity, instant merchant payouts, and repayments
 * @dev Only BNPLCore can pull funds for merchant settlements
 */
contract LiquidityPool is Ownable, ReentrancyGuard {
    // Custom errors
    error Unauthorized();
    error InsufficientLiquidity();
    error InvalidAmount();
    error InvalidToken();
    error TransferFailed();

    // Authorized contract
    address public bnplCore;

    // HTS-compatible stablecoin token
    IERC20HTS public paymentToken;

    // Protocol state
    uint256 public totalLiquidity;
    uint256 public outstandingCredit;
    uint256 public protocolFees;

    // Events
    event BNPLCoreSet(address indexed bnplCore);
    event PaymentTokenSet(address indexed token);
    event LiquidityDeposited(address indexed depositor, uint256 amount);
    event LiquidityWithdrawn(address indexed recipient, uint256 amount);
    event MerchantSettled(address indexed merchant, uint256 amount, uint256 indexed bnplId);
    event RepaymentReceived(address indexed user, uint256 amount, uint256 indexed bnplId);
    event FeesCollected(uint256 amount);
    event FeesWithdrawn(address indexed recipient, uint256 amount);

    /**
     * @notice Constructor
     * @param _paymentToken Address of HTS-compatible stablecoin
     */
    constructor(address _paymentToken) Ownable(msg.sender) {
        if (_paymentToken == address(0)) revert InvalidToken();
        paymentToken = IERC20HTS(_paymentToken);
    }

    /**
     * @notice Set the BNPLCore contract address
     * @param _bnplCore Address of BNPLCore contract
     */
    function setBNPLCore(address _bnplCore) external onlyOwner {
        if (_bnplCore == address(0)) revert();
        bnplCore = _bnplCore;
        emit BNPLCoreSet(_bnplCore);
    }

    /**
     * @notice Deposit liquidity into the pool
     * @param amount Amount of tokens to deposit
     */
    function depositLiquidity(uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidAmount();
        
        bool success = paymentToken.transferFrom(msg.sender, address(this), amount);
        if (!success) revert TransferFailed();
        
        totalLiquidity += amount;
        emit LiquidityDeposited(msg.sender, amount);
    }

    /**
     * @notice Withdraw liquidity from the pool (admin only)
     * @param amount Amount of tokens to withdraw
     * @param recipient Address to receive the tokens
     */
    function withdrawLiquidity(uint256 amount, address recipient) external onlyOwner nonReentrant {
        if (amount == 0) revert InvalidAmount();
        if (recipient == address(0)) revert();
        
        // Ensure we maintain sufficient liquidity for outstanding credit
        uint256 availableLiquidity = totalLiquidity - outstandingCredit;
        if (amount > availableLiquidity) revert InsufficientLiquidity();
        
        totalLiquidity -= amount;
        
        bool success = paymentToken.transfer(recipient, amount);
        if (!success) revert TransferFailed();
        
        emit LiquidityWithdrawn(recipient, amount);
    }

    /**
     * @notice Settle merchant payment instantly (only callable by BNPLCore)
     * @param merchant Address of the merchant
     * @param amount Amount to pay to merchant
     * @param bnplId BNPL transaction ID
     */
    function settleMerchant(
        address merchant,
        uint256 amount,
        uint256 bnplId
    ) external nonReentrant {
        if (msg.sender != bnplCore) revert Unauthorized();
        if (amount == 0) revert InvalidAmount();
        if (merchant == address(0)) revert();
        
        // Check sufficient liquidity
        if (totalLiquidity < amount) revert InsufficientLiquidity();
        
        // Update state
        totalLiquidity -= amount;
        outstandingCredit += amount;
        
        // Transfer to merchant
        bool success = paymentToken.transfer(merchant, amount);
        if (!success) revert TransferFailed();
        
        emit MerchantSettled(merchant, amount, bnplId);
    }

    /**
     * @notice Receive repayment from user (only callable by BNPLCore)
     * @param user Address of the user repaying
     * @param amount Amount being repaid
     * @param bnplId BNPL transaction ID
     */
    function receiveRepayment(
        address user,
        uint256 amount,
        uint256 bnplId
    ) external nonReentrant {
        if (msg.sender != bnplCore) revert Unauthorized();
        if (amount == 0) revert InvalidAmount();
        
        // Transfer from user to pool
        bool success = paymentToken.transferFrom(user, address(this), amount);
        if (!success) revert TransferFailed();
        
        // Update state
        totalLiquidity += amount;
        outstandingCredit -= amount;
        
        emit RepaymentReceived(user, amount, bnplId);
    }

    /**
     * @notice Collect protocol fees (only callable by BNPLCore)
     * @param amount Amount of fees to collect
     */
    function collectFees(uint256 amount) external {
        if (msg.sender != bnplCore) revert Unauthorized();
        if (amount == 0) revert InvalidAmount();
        
        protocolFees += amount;
        emit FeesCollected(amount);
    }

    /**
     * @notice Withdraw collected protocol fees (admin only)
     * @param amount Amount of fees to withdraw
     * @param recipient Address to receive the fees
     */
    function withdrawFees(uint256 amount, address recipient) external onlyOwner nonReentrant {
        if (amount == 0) revert InvalidAmount();
        if (recipient == address(0)) revert();
        if (amount > protocolFees) revert();
        
        protocolFees -= amount;
        
        bool success = paymentToken.transfer(recipient, amount);
        if (!success) revert TransferFailed();
        
        emit FeesWithdrawn(recipient, amount);
    }

    /**
     * @notice Get available liquidity (total - outstanding credit)
     * @return Available liquidity amount
     */
    function getAvailableLiquidity() external view returns (uint256) {
        return totalLiquidity > outstandingCredit ? totalLiquidity - outstandingCredit : 0;
    }

    /**
     * @notice Get pool balance
     * @return Current token balance of the pool
     */
    function getPoolBalance() external view returns (uint256) {
        return paymentToken.balanceOf(address(this));
    }

    /**
     * @notice Get pool utilization statistics
     * @return utilizationBps Utilization in basis points (10000 = 100%)
     * @return availableLiquidity Available liquidity amount
     * @return totalLiquidity Total liquidity amount
     * @return outstandingCredit Outstanding credit amount
     */
    function getPoolStats() external view returns (
        uint256 utilizationBps,
        uint256 availableLiquidity,
        uint256 totalLiquidity_,
        uint256 outstandingCredit_
    ) {
        totalLiquidity_ = totalLiquidity;
        outstandingCredit_ = outstandingCredit;
        availableLiquidity = totalLiquidity > outstandingCredit ? totalLiquidity - outstandingCredit : 0;
        
        if (totalLiquidity > 0) {
            utilizationBps = (outstandingCredit * 10000) / totalLiquidity;
        } else {
            utilizationBps = 0;
        }
    }
}
