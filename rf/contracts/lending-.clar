;; Resource Factory Lending Engine - Version 4
;; Factory pattern with nested resource pools and compartmentalized logic

;; === FACTORY CONFIGURATION ===
(define-constant FACTORY_OWNER tx-sender)
(define-constant PRECISION_MULTIPLIER u1000000)
(define-constant ANNUAL_TIME_UNITS u31536000)
(define-constant FULL_UTILIZATION u1000000)

;; === FACTORY ERROR REGISTRY ===
(define-constant ERR_FACTORY_ACCESS (err u401))
(define-constant ERR_INVALID_RESOURCE (err u402))
(define-constant ERR_RESOURCE_SHORTAGE (err u403))
(define-constant ERR_COLLATERAL_BREACH (err u404))
(define-constant ERR_FACTORY_OFFLINE (err u405))
(define-constant ERR_LIQUIDATION_INVALID (err u406))
(define-constant ERR_ACCOUNT_MISSING (err u407))
(define-constant ERR_OPERATION_BLOCKED (err u408))

;; === RESOURCE POOL STATE ===
(define-data-var resource-pool-balance uint u0)
(define-data-var deployed-resource-balance uint u0)
(define-data-var supply-yield-accumulator uint PRECISION_MULTIPLIER)
(define-data-var borrow-cost-accumulator uint PRECISION_MULTIPLIER)
(define-data-var last-factory-update uint u0)
(define-data-var factory-operational-status bool true)

;; === YIELD FACTORY PARAMETERS ===
(define-data-var factory-base-yield uint u20000)       ;; 2% factory base
(define-data-var factory-slope-primary uint u100000)   ;; 10% primary slope
(define-data-var factory-slope-secondary uint u600000) ;; 60% secondary slope
(define-data-var factory-optimal-point uint u800000)   ;; 80% optimal point

;; === RISK FACTORY PARAMETERS ===
(define-data-var factory-collateral-ratio uint u750000)  ;; 75% collateral ratio
(define-data-var factory-liquidation-reward uint u100000) ;; 10% liquidation reward
(define-data-var factory-protocol-share uint u100000)    ;; 10% protocol share

;; === NESTED ACCOUNT RESOURCES ===
(define-map supply-resource-accounts principal {
  resource-units: uint,
  yield-multiplier: uint,
  factory-timestamp: uint,
  resource-status: (string-ascii 15)
})

(define-map borrow-resource-accounts principal {
  debt-units: uint,
  cost-multiplier: uint,
  factory-timestamp: uint,
  resource-status: (string-ascii 15)
})

(define-map collateral-resource-vaults principal {
  vault-balance: uint,
  last-audit: uint,
  vault-status: (string-ascii 15)
})

;; === FACTORY ANALYTICS INTERFACE ===

(define-read-only (calculate-resource-utilization)
  (let ((available-resources (var-get resource-pool-balance))
        (deployed-resources (var-get deployed-resource-balance)))
    (if (is-eq available-resources u0)
        u0
        (let ((utilization (/ (* deployed-resources PRECISION_MULTIPLIER) available-resources)))
          (if (<= utilization FULL_UTILIZATION)
              utilization
              FULL_UTILIZATION)))))

(define-read-only (generate-borrowing-cost-rate)
  (let ((utilization-level (calculate-resource-utilization))
        (optimal-threshold (var-get factory-optimal-point))
        (base-cost (var-get factory-base-yield))
        (primary-slope (var-get factory-slope-primary))
        (secondary-slope (var-get factory-slope-secondary)))
    (if (<= utilization-level optimal-threshold)
        ;; Below optimal utilization
        (+ base-cost 
           (/ (* utilization-level primary-slope) PRECISION_MULTIPLIER))
        ;; Above optimal utilization - apply stress pricing
        (+ (+ base-cost primary-slope)
           (/ (* (- utilization-level optimal-threshold) secondary-slope)
              (- PRECISION_MULTIPLIER optimal-threshold))))))

(define-read-only (generate-supply-yield-rate)
  (let ((borrow-rate (generate-borrowing-cost-rate))
        (utilization-level (calculate-resource-utilization))
        (protocol-fee (var-get factory-protocol-share)))
    (/ (* (* borrow-rate utilization-level) (- PRECISION_MULTIPLIER protocol-fee))
       (* PRECISION_MULTIPLIER PRECISION_MULTIPLIER))))

(define-read-only (query-supply-resource-balance (account principal))
  (match (map-get? supply-resource-accounts account)
    account-resource
    (let ((normalized-units (get resource-units account-resource))
          (account-multiplier (get yield-multiplier account-resource))
          (current-multiplier (var-get supply-yield-accumulator)))
      (if (> account-multiplier u0)
          (/ (* normalized-units current-multiplier) account-multiplier)
          normalized-units))
    u0))

(define-read-only (query-borrow-resource-balance (account principal))
  (match (map-get? borrow-resource-accounts account)
    account-resource
    (let ((normalized-units (get debt-units account-resource))
          (account-multiplier (get cost-multiplier account-resource))
          (current-multiplier (var-get borrow-cost-accumulator)))
      (if (> account-multiplier u0)
          (/ (* normalized-units current-multiplier) account-multiplier)
          normalized-units))
    u0))

(define-read-only (query-collateral-vault-balance (account principal))
  (match (map-get? collateral-resource-vaults account)
    vault-resource (get vault-balance vault-resource)
    u0))

(define-read-only (assess-resource-health (account principal))
  (let ((vault-value (query-collateral-vault-balance account))
        (debt-value (query-borrow-resource-balance account))
        (required-ratio (var-get factory-collateral-ratio)))
    (if (is-eq debt-value u0)
        true
        (>= (/ (* vault-value required-ratio) PRECISION_MULTIPLIER) debt-value))))

;; === FACTORY RESOURCE PROCESSORS ===

(define-private (process-factory-accruals)
  (match (get-block-info? time (- block-height u1))
    current-timestamp
    (let ((last-update (var-get last-factory-update)))
      (if (> current-timestamp last-update)
          (let ((time-elapsed (- current-timestamp last-update))
                (borrow-rate (generate-borrowing-cost-rate))
                (supply-rate (generate-supply-yield-rate))
                (borrow-accrual (/ (* borrow-rate time-elapsed) ANNUAL_TIME_UNITS))
                (supply-accrual (/ (* supply-rate time-elapsed) ANNUAL_TIME_UNITS)))
            (var-set borrow-cost-accumulator 
                    (+ (var-get borrow-cost-accumulator) borrow-accrual))
            (var-set supply-yield-accumulator 
                    (+ (var-get supply-yield-accumulator) supply-accrual))
            (var-set last-factory-update current-timestamp)
            (ok true))
          (ok true)))
    (ok true)))

(define-private (validate-factory-operations)
  (ok (var-get factory-operational-status)))

(define-private (execute-resource-transfer (from-account principal) (to-account principal) (amount uint))
  (if (is-eq from-account tx-sender)
      (stx-transfer? amount from-account to-account)
      (as-contract (stx-transfer? amount from-account to-account))))

;; === SUPPLY RESOURCE FACTORY OPERATIONS ===

(define-public (create-supply-resource (deposit-amount uint))
  (begin
    (asserts! (> deposit-amount u0) ERR_INVALID_RESOURCE)
    (asserts! (is-ok (validate-factory-operations)) ERR_FACTORY_OFFLINE)
    (let ((accrual-result (process-factory-accruals))) true)
    
    (try! (execute-resource-transfer tx-sender (as-contract tx-sender) deposit-amount))
    
    (let ((current-multiplier (var-get supply-yield-accumulator))
          (resource-units (/ (* deposit-amount PRECISION_MULTIPLIER) current-multiplier))
          (factory-timestamp (default-to u0 (get-block-info? time (- block-height u1))))
          (existing-resource (default-to 
                             { resource-units: u0,
                               yield-multiplier: current-multiplier,
                               factory-timestamp: factory-timestamp,
                               resource-status: "ACTIVE" }
                             (map-get? supply-resource-accounts tx-sender))))
      
      (map-set supply-resource-accounts tx-sender {
        resource-units: (+ (get resource-units existing-resource) resource-units),
        yield-multiplier: current-multiplier,
        factory-timestamp: factory-timestamp,
        resource-status: "ACTIVE"
      })
      
      (var-set resource-pool-balance (+ (var-get resource-pool-balance) deposit-amount))
      (ok deposit-amount))))

(define-public (redeem-supply-resource (withdrawal-amount uint))
  (begin
    (asserts! (> withdrawal-amount u0) ERR_INVALID_RESOURCE)
    (asserts! (is-ok (validate-factory-operations)) ERR_FACTORY_OFFLINE)
    (let ((accrual-result (process-factory-accruals))) true)
    
    (let ((available-balance (query-supply-resource-balance tx-sender))
          (current-multiplier (var-get supply-yield-accumulator))
          (resource-units-to-burn (/ (* withdrawal-amount PRECISION_MULTIPLIER) current-multiplier))
          (existing-resource (unwrap! (map-get? supply-resource-accounts tx-sender) ERR_RESOURCE_SHORTAGE)))
      
      (asserts! (>= available-balance withdrawal-amount) ERR_RESOURCE_SHORTAGE)
      
      (map-set supply-resource-accounts tx-sender {
        resource-units: (- (get resource-units existing-resource) resource-units-to-burn),
        yield-multiplier: current-multiplier,
        factory-timestamp: (get factory-timestamp existing-resource),
        resource-status: (get resource-status existing-resource)
      })
      
      (var-set resource-pool-balance (- (var-get resource-pool-balance) withdrawal-amount))
      (try! (execute-resource-transfer (as-contract tx-sender) tx-sender withdrawal-amount))
      (ok withdrawal-amount))))

;; === COLLATERAL VAULT FACTORY OPERATIONS ===

(define-public (create-collateral-vault (vault-amount uint))
  (begin
    (asserts! (> vault-amount u0) ERR_INVALID_RESOURCE)
    (try! (execute-resource-transfer tx-sender (as-contract tx-sender) vault-amount))
    
    (let ((audit-timestamp (default-to u0 (get-block-info? time (- block-height u1))))
          (existing-vault-balance (query-collateral-vault-balance tx-sender)))
      
      (map-set collateral-resource-vaults tx-sender {
        vault-balance: (+ existing-vault-balance vault-amount),
        last-audit: audit-timestamp,
        vault-status: "SECURED"
      })
      (ok vault-amount))))

(define-public (withdraw-from-vault (release-amount uint))
  (begin
    (asserts! (> release-amount u0) ERR_INVALID_RESOURCE)
    (let ((accrual-result (process-factory-accruals))) true)
    
    (let ((current-vault-balance (query-collateral-vault-balance tx-sender))
          (current-debt (query-borrow-resource-balance tx-sender))
          (remaining-vault (- current-vault-balance release-amount))
          (required-ratio (var-get factory-collateral-ratio))
          (audit-timestamp (default-to u0 (get-block-info? time (- block-height u1)))))
      
      (asserts! (>= current-vault-balance release-amount) ERR_RESOURCE_SHORTAGE)
      
      ;; Validate post-withdrawal health
      (if (> current-debt u0)
          (asserts! (>= (/ (* remaining-vault required-ratio) PRECISION_MULTIPLIER) 
                       current-debt) ERR_COLLATERAL_BREACH)
          true)
      
      (map-set collateral-resource-vaults tx-sender {
        vault-balance: remaining-vault,
        last-audit: audit-timestamp,
        vault-status: "SECURED"
      })
      
      (try! (execute-resource-transfer (as-contract tx-sender) tx-sender release-amount))
      (ok release-amount))))

;; === BORROW RESOURCE FACTORY OPERATIONS ===

(define-public (create-borrow-resource (loan-amount uint))
  (begin
    (asserts! (> loan-amount u0) ERR_INVALID_RESOURCE)
    (asserts! (is-ok (validate-factory-operations)) ERR_FACTORY_OFFLINE)
    (let ((accrual-result (process-factory-accruals))) true)
    
    (let ((vault-value (query-collateral-vault-balance tx-sender))
          (existing-debt (query-borrow-resource-balance tx-sender))
          (required-ratio (var-get factory-collateral-ratio))
          (max-borrowing-capacity (/ (* vault-value required-ratio) PRECISION_MULTIPLIER))
          (projected-total-debt (+ existing-debt loan-amount))
          (current-multiplier (var-get borrow-cost-accumulator))
          (debt-units (/ (* loan-amount PRECISION_MULTIPLIER) current-multiplier))
          (factory-timestamp (default-to u0 (get-block-info? time (- block-height u1))))
          (existing-resource (default-to 
                             { debt-units: u0,
                               cost-multiplier: current-multiplier,
                               factory-timestamp: factory-timestamp,
                               resource-status: "ACTIVE" }
                             (map-get? borrow-resource-accounts tx-sender))))
      
      (asserts! (>= max-borrowing-capacity projected-total-debt) ERR_COLLATERAL_BREACH)
      (asserts! (>= (var-get resource-pool-balance) loan-amount) ERR_RESOURCE_SHORTAGE)
      
      (map-set borrow-resource-accounts tx-sender {
        debt-units: (+ (get debt-units existing-resource) debt-units),
        cost-multiplier: current-multiplier,
        factory-timestamp: factory-timestamp,
        resource-status: "ACTIVE"
      })
      
      (var-set deployed-resource-balance (+ (var-get deployed-resource-balance) loan-amount))
      (var-set resource-pool-balance (- (var-get resource-pool-balance) loan-amount))
      
      (try! (execute-resource-transfer (as-contract tx-sender) tx-sender loan-amount))
      (ok loan-amount))))

(define-public (repay-borrow-resource (repayment-amount uint))
  (begin
    (asserts! (> repayment-amount u0) ERR_INVALID_RESOURCE)
    (let ((accrual-result (process-factory-accruals))) true)
    
    (let ((current-debt (query-borrow-resource-balance tx-sender))
          (effective-repayment (if (> repayment-amount current-debt) current-debt repayment-amount))
          (current-multiplier (var-get borrow-cost-accumulator))
          (debt-units-to-burn (/ (* effective-repayment PRECISION_MULTIPLIER) current-multiplier))
          (existing-resource (unwrap! (map-get? borrow-resource-accounts tx-sender) ERR_ACCOUNT_MISSING)))
      
      (asserts! (> current-debt u0) ERR_ACCOUNT_MISSING)
      (try! (execute-resource-transfer tx-sender (as-contract tx-sender) effective-repayment))
      
      (map-set borrow-resource-accounts tx-sender {
        debt-units: (- (get debt-units existing-resource) debt-units-to-burn),
        cost-multiplier: current-multiplier,
        factory-timestamp: (get factory-timestamp existing-resource),
        resource-status: (get resource-status existing-resource)
      })
      
      (var-set deployed-resource-balance (- (var-get deployed-resource-balance) effective-repayment))
      (var-set resource-pool-balance (+ (var-get resource-pool-balance) effective-repayment))
      (ok effective-repayment))))

;; === LIQUIDATION RESOURCE FACTORY ===

(define-public (execute-resource-liquidation (target-account principal) (coverage-amount uint))
  (begin
    (asserts! (> coverage-amount u0) ERR_INVALID_RESOURCE)
    (asserts! (not (assess-resource-health target-account)) ERR_LIQUIDATION_INVALID)
    (let ((accrual-result (process-factory-accruals))) true)
    
    (let ((target-debt (query-borrow-resource-balance target-account))
          (target-vault (query-collateral-vault-balance target-account))
          (reward-rate (var-get factory-liquidation-reward))
          (effective-coverage (if (> coverage-amount target-debt) target-debt coverage-amount))
          (vault-seizure (+ effective-coverage 
                          (/ (* effective-coverage reward-rate) PRECISION_MULTIPLIER))))
      
      (asserts! (<= vault-seizure target-vault) ERR_RESOURCE_SHORTAGE)
      (try! (execute-resource-transfer tx-sender (as-contract tx-sender) effective-coverage))
      
      ;; Update target's borrow resource
      (let ((current-multiplier (var-get borrow-cost-accumulator))
            (debt-units-to-burn (/ (* effective-coverage PRECISION_MULTIPLIER) current-multiplier))
            (existing-borrow-resource (unwrap! (map-get? borrow-resource-accounts target-account) ERR_ACCOUNT_MISSING)))
        (map-set borrow-resource-accounts target-account {
          debt-units: (- (get debt-units existing-borrow-resource) debt-units-to-burn),
          cost-multiplier: current-multiplier,
          factory-timestamp: (get factory-timestamp existing-borrow-resource),
          resource-status: "LIQUIDATED"
        }))
      
      ;; Update target's collateral vault
      (let ((audit-timestamp (default-to u0 (get-block-info? time (- block-height u1)))))
        (map-set collateral-resource-vaults target-account {
          vault-balance: (- target-vault vault-seizure),
          last-audit: audit-timestamp,
          vault-status: "LIQUIDATED"
        }))
      
      ;; Transfer seized vault resources to liquidator
      (try! (execute-resource-transfer (as-contract tx-sender) tx-sender vault-seizure))
      
      ;; Update factory resource pools
      (var-set deployed-resource-balance (- (var-get deployed-resource-balance) effective-coverage))
      (var-set resource-pool-balance (+ (var-get resource-pool-balance) effective-coverage))
      (ok vault-seizure))))

;; === FACTORY ADMINISTRATION ===

(define-public (reconfigure-yield-factory (new-base uint) (new-primary uint) (new-secondary uint) (new-optimal uint))
  (begin
    (asserts! (is-eq tx-sender FACTORY_OWNER) ERR_FACTORY_ACCESS)
    (var-set factory-base-yield new-base)
    (var-set factory-slope-primary new-primary)
    (var-set factory-slope-secondary new-secondary)
    (var-set factory-optimal-point new-optimal)
    (ok true)))

(define-public (reconfigure-risk-factory (new-ratio uint) (new-reward uint) (new-share uint))
  (begin
    (asserts! (is-eq tx-sender FACTORY_OWNER) ERR_FACTORY_ACCESS)
    (var-set factory-collateral-ratio new-ratio)
    (var-set factory-liquidation-reward new-reward)
    (var-set factory-protocol-share new-share)
    (ok true)))

(define-public (toggle-factory-operations (operational bool))
  (begin
    (asserts! (is-eq tx-sender FACTORY_OWNER) ERR_FACTORY_ACCESS)
    (var-set factory-operational-status operational)
    (ok true)))

(define-public (bootstrap-factory-state)
  (begin
    (asserts! (is-eq tx-sender FACTORY_OWNER) ERR_FACTORY_ACCESS)
    (match (get-block-info? time (- block-height u1))
      timestamp (var-set last-factory-update timestamp)
      false)
    (ok true)))