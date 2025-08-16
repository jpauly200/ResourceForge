# ResourceForge

**A Factory-Pattern Lending Engine for Stacks Blockchain**

ResourceForge is a sophisticated DeFi lending protocol built on the Stacks blockchain using Clarity smart contracts. It implements a factory pattern architecture with nested resource pools, dynamic yield calculation, and automated liquidation mechanisms.

## 🏗️ Architecture Overview

ResourceForge operates as a comprehensive lending factory with three core resource types:

- **Supply Resources**: Deposit assets to earn yield
- **Borrow Resources**: Take loans against collateral
- **Collateral Vaults**: Secure borrowing positions

### Key Features

- **Dynamic Interest Rates**: Utilization-based rate model with optimal threshold targeting
- **Factory Pattern Design**: Modular, compartmentalized resource management
- **Automated Liquidations**: Health-based position monitoring with liquidation rewards
- **Precision Mathematics**: High-precision calculations using 6-decimal fixed-point arithmetic
- **Yield Accrual System**: Time-based compound interest accumulation

## 📊 Protocol Mechanics

### Interest Rate Model

The protocol uses a dual-slope interest rate model:

- **Base Rate**: 2% annual
- **Primary Slope**: 10% (below optimal utilization)
- **Secondary Slope**: 60% (above optimal utilization)
- **Optimal Utilization**: 80%

Interest rates dynamically adjust based on pool utilization to incentivize balanced supply and demand.

### Collateralization

- **Collateral Ratio**: 75% (configurable)
- **Liquidation Reward**: 10% bonus for liquidators
- **Health Factor**: Continuous monitoring of position safety

## 🚀 Core Operations

### Supply Operations

```clarity
;; Deposit assets to earn yield
(create-supply-resource deposit-amount)

;; Withdraw supplied assets plus accrued yield
(redeem-supply-resource withdrawal-amount)
```

### Collateral Management

```clarity
;; Deposit collateral to secure borrowing
(create-collateral-vault vault-amount)

;; Withdraw collateral (subject to health checks)
(withdraw-from-vault release-amount)
```

### Borrowing Operations

```clarity
;; Borrow against collateral
(create-borrow-resource loan-amount)

;; Repay borrowed amount
(repay-borrow-resource repayment-amount)
```

### Liquidations

```clarity
;; Liquidate unhealthy positions
(execute-resource-liquidation target-account coverage-amount)
```

## 📈 Analytics & Monitoring

The protocol provides comprehensive read-only functions for monitoring:

- **Utilization Rates**: Real-time pool utilization calculation
- **Interest Rates**: Current borrowing and supply rates
- **Account Health**: Position safety assessment
- **Balance Queries**: Individual account balances across all resource types

### Key Analytics Functions

```clarity
(calculate-resource-utilization)
(generate-borrowing-cost-rate)
(generate-supply-yield-rate)
(assess-resource-health account)
(query-supply-resource-balance account)
(query-borrow-resource-balance account)
(query-collateral-vault-balance account)
```

## 🔧 Technical Specifications

### Precision & Constants

- **Precision Multiplier**: 1,000,000 (6 decimal places)
- **Annual Time Units**: 31,536,000 seconds
- **Full Utilization**: 100% (1,000,000 in precision units)

### Error Codes

| Code | Error | Description |
|------|-------|-------------|
| 401 | ERR_FACTORY_ACCESS | Unauthorized factory access |
| 402 | ERR_INVALID_RESOURCE | Invalid resource amount |
| 403 | ERR_RESOURCE_SHORTAGE | Insufficient resources |
| 404 | ERR_COLLATERAL_BREACH | Collateral requirement violation |
| 405 | ERR_FACTORY_OFFLINE | Factory operations suspended |
| 406 | ERR_LIQUIDATION_INVALID | Invalid liquidation attempt |
| 407 | ERR_ACCOUNT_MISSING | Account not found |
| 408 | ERR_OPERATION_BLOCKED | Operation currently blocked |

## 🛡️ Security Features

### Access Controls
- Factory owner privileges for parameter updates
- Operation toggle for emergency shutdowns
- Account-based resource isolation

### Safety Mechanisms
- Health factor monitoring
- Collateral adequacy checks
- Liquidation threshold enforcement
- Precision overflow protection

### Audit Trail
- Timestamp tracking for all operations
- Status flags for resource states
- Comprehensive state validation

## 🎛️ Administration

Factory owners can configure key parameters:

### Yield Factory Configuration
```clarity
(reconfigure-yield-factory base-rate primary-slope secondary-slope optimal-point)
```

### Risk Factory Configuration
```clarity
(reconfigure-risk-factory collateral-ratio liquidation-reward protocol-share)
```

### Operational Controls
```clarity
(toggle-factory-operations enabled)
(bootstrap-factory-state)
```

## 🔄 State Management

The protocol maintains several critical state variables:

- **Resource Pool Balance**: Available liquidity for lending
- **Deployed Resource Balance**: Currently borrowed amounts
- **Yield/Cost Accumulators**: Compound interest tracking
- **Factory Update Timestamp**: Last accrual processing time
- **Operational Status**: Factory on/off state

## 💡 Use Cases

### For Suppliers
- Earn competitive yields on STX holdings
- Automated compound interest accrual
- Flexible withdrawal options

### For Borrowers  
- Access liquidity without selling assets
- Competitive interest rates
- Flexible repayment terms

### For Liquidators
- Earn liquidation rewards
- Help maintain protocol health
- Automated opportunity detection

## 🚧 Development Status

ResourceForge is a Version 4 implementation featuring:
- Enhanced factory pattern architecture
- Improved resource compartmentalization  
- Advanced yield calculation mechanisms
- Robust liquidation systems

## 📄 License

This project is part of the Stacks ecosystem. Please ensure compliance with relevant licensing requirements when deploying or modifying the code.

## 🤝 Contributing

ResourceForge follows factory pattern principles and modular design. When contributing:
- Maintain precision arithmetic standards
- Follow existing error handling patterns
- Ensure comprehensive testing of state transitions
- Document all parameter changes and their implications
