;; Enhanced Simple Lending/Borrowing Platform
;; A decentralized lending protocol with liquidation, governance integration, and enhanced security

;; ===================
;; CONSTANTS & ERRORS
;; ===================

;; Error codes
(define-constant ERR-UNAUTHORIZED (err u401))
(define-constant ERR-INSUFFICIENT-BALANCE (err u402))
(define-constant ERR-INSUFFICIENT-COLLATERAL (err u403))
(define-constant ERR-LOAN-NOT-FOUND (err u404))
(define-constant ERR-INVALID-AMOUNT (err u405))
(define-constant ERR-LOAN-ALREADY-REPAID (err u406))
(define-constant ERR-COLLATERAL-RATIO-TOO-LOW (err u407))
(define-constant ERR-LOAN-HEALTHY (err u408))
(define-constant ERR-LIQUIDATION-FAILED (err u409))
(define-constant ERR-CONTRACT-PAUSED (err u410))
(define-constant ERR-COOLDOWN-ACTIVE (err u411))
(define-constant ERR-INVALID-GOVERNANCE-CONTRACT (err u412))

;; Contract constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant LIQUIDATION-THRESHOLD u120) ;; 120% - can liquidate below this
(define-constant LIQUIDATION-PENALTY u10) ;; 10% penalty for liquidation
(define-constant BLOCKS-PER-YEAR u52560) ;; Approximate blocks per year
(define-constant MIN-LOAN-AMOUNT u100000) ;; 0.1 STX minimum loan
(define-constant MAX-LOAN-AMOUNT u100000000) ;; 100 STX maximum loan
(define-constant COOLDOWN-PERIOD u144) ;; 1 day cooldown between large operations

;; ===================
;; DATA VARIABLES
;; ===================

;; Global contract state
(define-data-var total-deposits uint u0)
(define-data-var total-borrowed uint u0)
(define-data-var loan-id-nonce uint u0)
(define-data-var contract-paused bool false)
(define-data-var governance-contract (optional principal) none)

;; Dynamic parameters (can be updated by governance)
(define-data-var current-interest-rate uint u500) ;; 5% annual interest (500 basis points)
(define-data-var current-collateral-ratio uint u150) ;; 150% collateralization required

;; ===================
;; DATA MAPS
;; ===================

;; User deposit balances and timestamps
(define-map user-deposits
    { user: principal }
    { 
        balance: uint,
        last-update-block: uint,
        last-large-operation: uint
    }
)

;; Individual loan records
(define-map loans
    { loan-id: uint }
    {
        borrower: principal,
        principal-amount: uint,
        collateral-amount: uint,
        start-block: uint,
        last-interest-update: uint,
        accumulated-interest: uint,
        is-repaid: bool
    }
)

;; User's active loan IDs (for tracking multiple loans per user)
(define-map user-loans
    { user: principal }
    { loan-ids: (list 10 uint) }
)

;; Liquidation records
(define-map liquidations
    { loan-id: uint }
    {
        liquidator: principal,
        liquidation-block: uint,
        penalty-amount: uint,
        collateral-seized: uint
    }
)

;; User reputation scores
(define-map user-reputation
    { user: principal }
    {
        successful-repayments: uint,
        total-loans: uint,
        liquidations: uint,
        reputation-score: uint
    }
)

;; ===================
;; PRIVATE FUNCTIONS
;; ===================

;; Helper function to get minimum of two values
(define-private (min-uint (a uint) (b uint))
    (if (<= a b) a b)
)

;; Helper function to get maximum of two values
(define-private (max-uint (a uint) (b uint))
    (if (>= a b) a b)
)

;; Calculate interest earned on deposits
(define-private (calculate-deposit-interest (balance uint) (blocks-elapsed uint))
    (let (
        (annual-interest (/ (* balance (var-get current-interest-rate)) u10000))
        (interest (/ (* annual-interest blocks-elapsed) BLOCKS-PER-YEAR))
    )
    interest)
)

;; Calculate interest owed on loans
(define-private (calculate-loan-interest (principal uint) (blocks-elapsed uint))
    (let (
        (annual-interest (/ (* principal (var-get current-interest-rate)) u10000))
        (interest (/ (* annual-interest blocks-elapsed) BLOCKS-PER-YEAR))
    )
    interest)
)

;; Check if collateral ratio is sufficient
(define-private (is-collateral-sufficient (loan-amount uint) (collateral-amount uint))
    (>= (* collateral-amount u100) (* loan-amount (var-get current-collateral-ratio)))
)

;; Check if loan can be liquidated
(define-private (can-liquidate-loan (loan-id uint))
    (let (
        (loan (unwrap! (map-get? loans { loan-id: loan-id }) false))
        (principal-amount (get principal-amount loan))
        (collateral-amount (get collateral-amount loan))
        (start-block (get start-block loan))
        (last-update (get last-interest-update loan))
        (accumulated-interest (get accumulated-interest loan))
        (blocks-since-update (- block-height last-update))
        (new-interest (calculate-loan-interest principal-amount blocks-since-update))
        (total-debt (+ principal-amount accumulated-interest new-interest))
        (current-ratio (/ (* collateral-amount u100) total-debt))
    )
    (and (not (get is-repaid loan)) (< current-ratio LIQUIDATION-THRESHOLD)))
)

;; Get next loan ID
(define-private (get-next-loan-id)
    (let (
        (current-id (var-get loan-id-nonce))
        (next-id (+ current-id u1))
    )
    (var-set loan-id-nonce next-id)
    next-id)
)

;; Add loan ID to user's loan list
(define-private (add-user-loan (user principal) (loan-id uint))
    (let (
        (current-loans (default-to { loan-ids: (list) } (map-get? user-loans { user: user })))
        (updated-loans (unwrap-panic (as-max-len? (append (get loan-ids current-loans) loan-id) u10)))
    )
    (map-set user-loans { user: user } { loan-ids: updated-loans })
    )
)

;; Update user reputation
(define-private (update-reputation (user principal) (loan-repaid bool) (was-liquidated bool))
    (let (
        (current-rep (default-to { successful-repayments: u0, total-loans: u0, liquidations: u0, reputation-score: u100 } 
                     (map-get? user-reputation { user: user })))
        (new-total-loans (+ (get total-loans current-rep) u1))
        (new-successful (if loan-repaid (+ (get successful-repayments current-rep) u1) (get successful-repayments current-rep)))
        (new-liquidations (if was-liquidated (+ (get liquidations current-rep) u1) (get liquidations current-rep)))
        (success-rate (if (> new-total-loans u0) (/ (* new-successful u100) new-total-loans) u0))
        (liquidation-penalty (if (> new-liquidations u0) (* new-liquidations u5) u0))
        (new-score (max-uint u0 (- success-rate liquidation-penalty)))
    )
    (map-set user-reputation 
        { user: user }
        {
            successful-repayments: new-successful,
            total-loans: new-total-loans,
            liquidations: new-liquidations,
            reputation-score: new-score
        }
    ))
)

;; Check cooldown period
(define-private (check-cooldown (user principal))
    (let (
        (deposit-info (map-get? user-deposits { user: user }))
    )
    (match deposit-info
        deposit-data (let ((last-operation (get last-large-operation deposit-data)))
                          (>= (- block-height last-operation) COOLDOWN-PERIOD))
        true ;; No previous operations
    ))
)

;; ===================
;; GOVERNANCE INTEGRATION
;; ===================

;; Set governance contract (owner only)
(define-public (set-governance-contract (governance-principal principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (var-set governance-contract (some governance-principal))
        (ok true)
    )
)

;; Update interest rate (governance only)
(define-public (update-interest-rate (new-rate uint))
    (let (
        (governance (unwrap! (var-get governance-contract) ERR-INVALID-GOVERNANCE-CONTRACT))
    )
    (asserts! (is-eq tx-sender governance) ERR-UNAUTHORIZED)
    (asserts! (and (>= new-rate u100) (<= new-rate u2000)) ERR-INVALID-AMOUNT) ;; 1% to 20%
    (var-set current-interest-rate new-rate)
    (ok new-rate))
)

;; Update collateral ratio (governance only)
(define-public (update-collateral-ratio (new-ratio uint))
    (let (
        (governance (unwrap! (var-get governance-contract) ERR-INVALID-GOVERNANCE-CONTRACT))
    )
    (asserts! (is-eq tx-sender governance) ERR-UNAUTHORIZED)
    (asserts! (and (>= new-ratio u110) (<= new-ratio u300)) ERR-INVALID-AMOUNT) ;; 110% to 300%
    (var-set current-collateral-ratio new-ratio)
    (ok new-ratio))
)

;; ===================
;; ADMIN FUNCTIONS
;; ===================

;; Emergency pause contract
(define-public (pause-contract)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (var-set contract-paused true)
        (ok true)
    )
)

;; Unpause contract
(define-public (unpause-contract)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (var-set contract-paused false)
        (ok true)
    )
)

;; ===================
;; PUBLIC FUNCTIONS
;; ===================

;; Deposit STX to earn interest
(define-public (deposit-stx (amount uint))
    (let (
        (sender tx-sender)
        (current-deposit (default-to { balance: u0, last-update-block: block-height, last-large-operation: u0 } 
                         (map-get? user-deposits { user: sender })))
        (current-balance (get balance current-deposit))
        (last-update (get last-update-block current-deposit))
        (blocks-elapsed (- block-height last-update))
        (earned-interest (calculate-deposit-interest current-balance blocks-elapsed))
        (new-balance (+ current-balance amount earned-interest))
        (is-large-deposit (> amount u10000000)) ;; 10 STX threshold for cooldown
    )
    (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (if is-large-deposit (check-cooldown sender) true) ERR-COOLDOWN-ACTIVE)
    
    ;; Transfer STX from user to contract
    (try! (stx-transfer? amount sender (as-contract tx-sender)))
    
    ;; Update user deposit record
    (map-set user-deposits 
        { user: sender }
        { 
            balance: new-balance,
            last-update-block: block-height,
            last-large-operation: (if is-large-deposit block-height (get last-large-operation current-deposit))
        }
    )
    
    ;; Update global state
    (var-set total-deposits (+ (var-get total-deposits) amount))
    
    (ok { deposited: amount, new-balance: new-balance, interest-earned: earned-interest })
    )
)

;; Withdraw deposited STX plus interest
(define-public (withdraw-stx (amount uint))
    (let (
        (sender tx-sender)
        (current-deposit (unwrap! (map-get? user-deposits { user: sender }) ERR-INSUFFICIENT-BALANCE))
        (current-balance (get balance current-deposit))
        (last-update (get last-update-block current-deposit))
        (blocks-elapsed (- block-height last-update))
        (earned-interest (calculate-deposit-interest current-balance blocks-elapsed))
        (total-available (+ current-balance earned-interest))
        (remaining-balance (- total-available amount))
        (is-large-withdrawal (> amount u10000000)) ;; 10 STX threshold for cooldown
    )
    (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (>= total-available amount) ERR-INSUFFICIENT-BALANCE)
    (asserts! (if is-large-withdrawal (check-cooldown sender) true) ERR-COOLDOWN-ACTIVE)
    
    ;; Transfer STX from contract to user
    (try! (as-contract (stx-transfer? amount tx-sender sender)))
    
    ;; Update user deposit record
    (if (> remaining-balance u0)
        (map-set user-deposits 
            { user: sender }
            { 
                balance: remaining-balance,
                last-update-block: block-height,
                last-large-operation: (if is-large-withdrawal block-height (get last-large-operation current-deposit))
            }
        )
        (map-delete user-deposits { user: sender })
    )
    
    ;; Update global state
    (var-set total-deposits (- (var-get total-deposits) amount))
    
    (ok { withdrawn: amount, remaining-balance: remaining-balance, interest-earned: earned-interest })
    )
)

;; Borrow STX by providing collateral
(define-public (borrow-stx (loan-amount uint) (collateral-amount uint))
    (let (
        (sender tx-sender)
        (loan-id (get-next-loan-id))
        (reputation (default-to { reputation-score: u100 } (map-get? user-reputation { user: sender })))
        (rep-score (get reputation-score reputation))
        (adjusted-collateral-ratio (if (>= rep-score u80) 
                                   (- (var-get current-collateral-ratio) u10) ;; 10% discount for good reputation
                                   (var-get current-collateral-ratio)))
    )
    (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
    (asserts! (and (>= loan-amount MIN-LOAN-AMOUNT) (<= loan-amount MAX-LOAN-AMOUNT)) ERR-INVALID-AMOUNT)
    (asserts! (> collateral-amount u0) ERR-INVALID-AMOUNT)
    (asserts! (>= (* collateral-amount u100) (* loan-amount adjusted-collateral-ratio)) ERR-INSUFFICIENT-COLLATERAL)
    (asserts! (>= (stx-get-balance (as-contract tx-sender)) loan-amount) ERR-INSUFFICIENT-BALANCE)
    
    ;; Transfer collateral from user to contract
    (try! (stx-transfer? collateral-amount sender (as-contract tx-sender)))
    
    ;; Transfer loan amount from contract to user
    (try! (as-contract (stx-transfer? loan-amount tx-sender sender)))
    
    ;; Create loan record
    (map-set loans
        { loan-id: loan-id }
        {
            borrower: sender,
            principal-amount: loan-amount,
            collateral-amount: collateral-amount,
            start-block: block-height,
            last-interest-update: block-height,
            accumulated-interest: u0,
            is-repaid: false
        }
    )
    
    ;; Add loan to user's loan list
    (add-user-loan sender loan-id)
    
    ;; Update reputation
    (update-reputation sender false false)
    
    ;; Update global state
    (var-set total-borrowed (+ (var-get total-borrowed) loan-amount))
    
    (ok { loan-id: loan-id, borrowed: loan-amount, collateral: collateral-amount, collateral-ratio-used: adjusted-collateral-ratio })
    )
)

;; Repay loan and get collateral back
(define-public (repay-loan (loan-id uint))
    (let (
        (sender tx-sender)
        (loan (unwrap! (map-get? loans { loan-id: loan-id }) ERR-LOAN-NOT-FOUND))
        (borrower (get borrower loan))
        (principal-amount (get principal-amount loan))
        (collateral-amount (get collateral-amount loan))
        (last-update (get last-interest-update loan))
        (accumulated-interest (get accumulated-interest loan))
        (is-repaid (get is-repaid loan))
        (blocks-elapsed (- block-height last-update))
        (new-interest (calculate-loan-interest principal-amount blocks-elapsed))
        (total-interest (+ accumulated-interest new-interest))
        (total-repayment (+ principal-amount total-interest))
    )
    (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
    (asserts! (is-eq sender borrower) ERR-UNAUTHORIZED)
    (asserts! (not is-repaid) ERR-LOAN-ALREADY-REPAID)
    
    ;; Transfer repayment from user to contract
    (try! (stx-transfer? total-repayment sender (as-contract tx-sender)))
    
    ;; Return collateral to borrower
    (try! (as-contract (stx-transfer? collateral-amount tx-sender sender)))
    
    ;; Mark loan as repaid
    (map-set loans
        { loan-id: loan-id }
        (merge loan { 
            is-repaid: true,
            last-interest-update: block-height,
            accumulated-interest: total-interest
        })
    )
    
    ;; Update reputation
    (update-reputation sender true false)
    
    ;; Update global state
    (var-set total-borrowed (- (var-get total-borrowed) principal-amount))
    
    (ok { 
        loan-id: loan-id, 
        principal-repaid: principal-amount, 
        interest-paid: total-interest,
        collateral-returned: collateral-amount 
    })
    )
)

;; Liquidate an undercollateralized loan
(define-public (liquidate-loan (loan-id uint))
    (let (
        (sender tx-sender)
        (loan (unwrap! (map-get? loans { loan-id: loan-id }) ERR-LOAN-NOT-FOUND))
        (borrower (get borrower loan))
        (principal-amount (get principal-amount loan))
        (collateral-amount (get collateral-amount loan))
        (last-update (get last-interest-update loan))
        (accumulated-interest (get accumulated-interest loan))
        (blocks-elapsed (- block-height last-update))
        (new-interest (calculate-loan-interest principal-amount blocks-elapsed))
        (total-debt (+ principal-amount accumulated-interest new-interest))
        (penalty-amount (/ (* collateral-amount LIQUIDATION-PENALTY) u100))
        (liquidator-reward penalty-amount)
        (remaining-collateral (- collateral-amount penalty-amount))
    )
    (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
    (asserts! (not (get is-repaid loan)) ERR-LOAN-ALREADY-REPAID)
    (asserts! (can-liquidate-loan loan-id) ERR-LOAN-HEALTHY)
    
    ;; Pay liquidator the penalty amount
    (try! (as-contract (stx-transfer? liquidator-reward tx-sender sender)))
    
    ;; Return remaining collateral to borrower (if any) - FIXED TYPE ISSUE
    (if (> remaining-collateral u0)
        (begin
            (try! (as-contract (stx-transfer? remaining-collateral tx-sender borrower)))
            true
        )
        true
    )
    
    ;; Mark loan as repaid (liquidated)
    (map-set loans
        { loan-id: loan-id }
        (merge loan { 
            is-repaid: true,
            last-interest-update: block-height,
            accumulated-interest: (+ accumulated-interest new-interest)
        })
    )
    
    ;; Record liquidation
    (map-set liquidations
        { loan-id: loan-id }
        {
            liquidator: sender,
            liquidation-block: block-height,
            penalty-amount: penalty-amount,
            collateral-seized: collateral-amount
        }
    )
    
    ;; Update borrower reputation
    (update-reputation borrower false true)
    
    ;; Update global state
    (var-set total-borrowed (- (var-get total-borrowed) principal-amount))
    
    (ok { 
        loan-id: loan-id,
        liquidator-reward: liquidator-reward,
        borrower-return: remaining-collateral,
        total-debt: total-debt
    })
    )
)

;; ===================
;; READ-ONLY FUNCTIONS
;; ===================

;; Get user's deposit balance with accrued interest
(define-read-only (get-user-balance (user principal))
    (let (
        (deposit (default-to { balance: u0, last-update-block: block-height, last-large-operation: u0 } 
                 (map-get? user-deposits { user: user })))
        (current-balance (get balance deposit))
        (last-update (get last-update-block deposit))
        (blocks-elapsed (- block-height last-update))
        (earned-interest (calculate-deposit-interest current-balance blocks-elapsed))
    )
    {
        balance: current-balance,
        earned-interest: earned-interest,
        total-balance: (+ current-balance earned-interest),
        last-update-block: last-update,
        cooldown-remaining: (max-uint u0 (- COOLDOWN-PERIOD (- block-height (get last-large-operation deposit))))
    })
)

;; Get loan details with current interest
(define-read-only (get-loan-details (loan-id uint))
    (let (
        (loan (unwrap! (map-get? loans { loan-id: loan-id }) ERR-LOAN-NOT-FOUND))
        (principal-amount (get principal-amount loan))
        (collateral-amount (get collateral-amount loan))
        (last-update (get last-interest-update loan))
        (accumulated-interest (get accumulated-interest loan))
        (blocks-elapsed (- block-height last-update))
        (new-interest (calculate-loan-interest principal-amount blocks-elapsed))
        (total-interest (+ accumulated-interest new-interest))
        (total-debt (+ principal-amount total-interest))
        (current-ratio (if (> total-debt u0) (/ (* collateral-amount u100) total-debt) u0))
        (health-factor (if (> LIQUIDATION-THRESHOLD u0) (/ current-ratio LIQUIDATION-THRESHOLD) u0))
    )
    (ok {
        loan: loan,
        current-interest: new-interest,
        total-interest: total-interest,
        total-debt: total-debt,
        current-collateral-ratio: current-ratio,
        health-factor: health-factor,
        can-be-liquidated: (can-liquidate-loan loan-id),
        blocks-elapsed: blocks-elapsed
    }))
)

;; Get user's active loans
(define-read-only (get-user-loans (user principal))
    (default-to { loan-ids: (list) } (map-get? user-loans { user: user }))
)

;; Get user reputation
(define-read-only (get-user-reputation (user principal))
    (default-to { successful-repayments: u0, total-loans: u0, liquidations: u0, reputation-score: u100 } 
               (map-get? user-reputation { user: user }))
)

;; Get liquidation details
(define-read-only (get-liquidation-details (loan-id uint))
    (map-get? liquidations { loan-id: loan-id })
)

;; Get contract statistics
(define-read-only (get-contract-stats)
    {
        total-deposits: (var-get total-deposits),
        total-borrowed: (var-get total-borrowed),
        contract-balance: (stx-get-balance (as-contract tx-sender)),
        available-liquidity: (- (stx-get-balance (as-contract tx-sender)) (var-get total-deposits)),
        total-loans: (var-get loan-id-nonce),
        current-interest-rate: (var-get current-interest-rate),
        current-collateral-ratio: (var-get current-collateral-ratio),
        contract-paused: (var-get contract-paused),
        governance-contract: (var-get governance-contract)
    }
)

;; Check if amount can be borrowed (liquidity check)
(define-read-only (can-borrow (amount uint))
    (let (
        (available (- (stx-get-balance (as-contract tx-sender)) (var-get total-deposits)))
    )
    (and (>= available amount) (not (var-get contract-paused))))
)

;; Calculate required collateral for a loan amount (with reputation discount)
(define-read-only (calculate-required-collateral (loan-amount uint) (user principal))
    (let (
        (reputation (default-to { reputation-score: u100 } (map-get? user-reputation { user: user })))
        (rep-score (get reputation-score reputation))
        (adjusted-ratio (if (>= rep-score u80) 
                        (- (var-get current-collateral-ratio) u10)
                        (var-get current-collateral-ratio)))
    )
    {
        required-collateral: (/ (* loan-amount adjusted-ratio) u100),
        collateral-ratio-used: adjusted-ratio,
        reputation-discount: (>= rep-score u80)
    })
)

;; Get all loans at risk of liquidation
(define-read-only (get-liquidatable-loans (loan-ids (list 20 uint)))
    (map can-liquidate-loan loan-ids)
)

;; Get protocol parameters
(define-read-only (get-protocol-parameters)
    {
        interest-rate: (var-get current-interest-rate),
        collateral-ratio: (var-get current-collateral-ratio),
        liquidation-threshold: LIQUIDATION-THRESHOLD,
        liquidation-penalty: LIQUIDATION-PENALTY,
        min-loan-amount: MIN-LOAN-AMOUNT,
        max-loan-amount: MAX-LOAN-AMOUNT,
        cooldown-period: COOLDOWN-PERIOD
    }
)
