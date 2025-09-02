;; Simple Lending/Borrowing Platform
;; A decentralized lending protocol allowing users to deposit, earn interest, and borrow with collateral

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

;; Contract constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant COLLATERAL-RATIO u150) ;; 150% collateralization required
(define-constant INTEREST-RATE u500) ;; 5% annual interest (500 basis points)
(define-constant BLOCKS-PER-YEAR u52560) ;; Approximate blocks per year

;; ===================
;; DATA VARIABLES
;; ===================

;; Global contract state
(define-data-var total-deposits uint u0)
(define-data-var total-borrowed uint u0)
(define-data-var loan-id-nonce uint u0)

;; ===================
;; DATA MAPS
;; ===================

;; User deposit balances and timestamps
(define-map user-deposits
    { user: principal }
    { 
        balance: uint,
        last-update-block: uint
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
        is-repaid: bool
    }
)

;; User's active loan IDs (for tracking multiple loans per user)
(define-map user-loans
    { user: principal }
    { loan-ids: (list 10 uint) }
)

;; ===================
;; PRIVATE FUNCTIONS
;; ===================

;; Calculate interest earned on deposits
(define-private (calculate-deposit-interest (balance uint) (blocks-elapsed uint))
    (let (
        (annual-interest (/ (* balance INTEREST-RATE) u10000))
        (interest (* annual-interest (/ blocks-elapsed BLOCKS-PER-YEAR)))
    )
    interest)
)

;; Calculate interest owed on loans
(define-private (calculate-loan-interest (principal uint) (blocks-elapsed uint))
    (let (
        (annual-interest (/ (* principal INTEREST-RATE) u10000))
        (interest (* annual-interest (/ blocks-elapsed BLOCKS-PER-YEAR)))
    )
    interest)
)

;; Check if collateral ratio is sufficient
(define-private (is-collateral-sufficient (loan-amount uint) (collateral-amount uint))
    (>= (* collateral-amount u100) (* loan-amount COLLATERAL-RATIO))
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

;; ===================
;; PUBLIC FUNCTIONS
;; ===================

;; Deposit STX to earn interest
(define-public (deposit-stx (amount uint))
    (let (
        (sender tx-sender)
        (current-deposit (default-to { balance: u0, last-update-block: block-height } 
                         (map-get? user-deposits { user: sender })))
        (current-balance (get balance current-deposit))
        (last-update (get last-update-block current-deposit))
        (blocks-elapsed (- block-height last-update))
        (earned-interest (calculate-deposit-interest current-balance blocks-elapsed))
        (new-balance (+ current-balance amount earned-interest))
    )
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    
    ;; Transfer STX from user to contract
    (try! (stx-transfer? amount sender (as-contract tx-sender)))
    
    ;; Update user deposit record
    (map-set user-deposits 
        { user: sender }
        { 
            balance: new-balance,
            last-update-block: block-height
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
    )
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (>= total-available amount) ERR-INSUFFICIENT-BALANCE)
    
    ;; Transfer STX from contract to user
    (try! (as-contract (stx-transfer? amount tx-sender sender)))
    
    ;; Update user deposit record
    (if (> remaining-balance u0)
        (map-set user-deposits 
            { user: sender }
            { 
                balance: remaining-balance,
                last-update-block: block-height
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
    )
    (asserts! (> loan-amount u0) ERR-INVALID-AMOUNT)
    (asserts! (> collateral-amount u0) ERR-INVALID-AMOUNT)
    (asserts! (is-collateral-sufficient loan-amount collateral-amount) ERR-INSUFFICIENT-COLLATERAL)
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
            is-repaid: false
        }
    )
    
    ;; Add loan to user's loan list
    (add-user-loan sender loan-id)
    
    ;; Update global state
    (var-set total-borrowed (+ (var-get total-borrowed) loan-amount))
    
    (ok { loan-id: loan-id, borrowed: loan-amount, collateral: collateral-amount })
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
        (start-block (get start-block loan))
        (is-repaid (get is-repaid loan))
        (blocks-elapsed (- block-height start-block))
        (interest-owed (calculate-loan-interest principal-amount blocks-elapsed))
        (total-repayment (+ principal-amount interest-owed))
    )
    (asserts! (is-eq sender borrower) ERR-UNAUTHORIZED)
    (asserts! (not is-repaid) ERR-LOAN-ALREADY-REPAID)
    
    ;; Transfer repayment from user to contract
    (try! (stx-transfer? total-repayment sender (as-contract tx-sender)))
    
    ;; Return collateral to borrower
    (try! (as-contract (stx-transfer? collateral-amount tx-sender sender)))
    
    ;; Mark loan as repaid
    (map-set loans
        { loan-id: loan-id }
        (merge loan { is-repaid: true })
    )
    
    ;; Update global state
    (var-set total-borrowed (- (var-get total-borrowed) principal-amount))
    
    (ok { 
        loan-id: loan-id, 
        principal-repaid: principal-amount, 
        interest-paid: interest-owed,
        collateral-returned: collateral-amount 
    })
    )
)

;; ===================
;; READ-ONLY FUNCTIONS
;; ===================

;; Get user's deposit balance with accrued interest
(define-read-only (get-user-balance (user principal))
    (let (
        (deposit (default-to { balance: u0, last-update-block: block-height } 
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
        last-update-block: last-update
    })
)

;; Get loan details
(define-read-only (get-loan-details (loan-id uint))
    (let (
        (loan (unwrap! (map-get? loans { loan-id: loan-id }) ERR-LOAN-NOT-FOUND))
        (principal-amount (get principal-amount loan))
        (start-block (get start-block loan))
        (blocks-elapsed (- block-height start-block))
        (interest-owed (calculate-loan-interest principal-amount blocks-elapsed))
    )
    (ok {
        loan: loan,
        interest-owed: interest-owed,
        total-owed: (+ principal-amount interest-owed),
        blocks-elapsed: blocks-elapsed
    }))
)

;; Get user's active loans
(define-read-only (get-user-loans (user principal))
    (default-to { loan-ids: (list) } (map-get? user-loans { user: user }))
)

;; Get contract statistics
(define-read-only (get-contract-stats)
    {
        total-deposits: (var-get total-deposits),
        total-borrowed: (var-get total-borrowed),
        contract-balance: (stx-get-balance (as-contract tx-sender)),
        available-liquidity: (- (stx-get-balance (as-contract tx-sender)) (var-get total-deposits)),
        total-loans: (var-get loan-id-nonce)
    }
)

;; Check if amount can be borrowed (liquidity check)
(define-read-only (can-borrow (amount uint))
    (let (
        (available (- (stx-get-balance (as-contract tx-sender)) (var-get total-deposits)))
    )
    (>= available amount))
)

;; Calculate required collateral for a loan amount
(define-read-only (calculate-required-collateral (loan-amount uint))
    (/ (* loan-amount COLLATERAL-RATIO) u100)
)
