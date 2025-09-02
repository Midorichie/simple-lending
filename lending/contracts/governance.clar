;; Governance Contract for Simple Lending Platform
;; Allows platform users to propose and vote on protocol changes

;; ===================
;; CONSTANTS & ERRORS
;; ===================

;; Error codes
(define-constant ERR-UNAUTHORIZED (err u601))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u602))
(define-constant ERR-ALREADY-VOTED (err u603))
(define-constant ERR-VOTING-PERIOD-ENDED (err u604))
(define-constant ERR-VOTING-PERIOD-ACTIVE (err u605))
(define-constant ERR-INSUFFICIENT-STAKE (err u606))
(define-constant ERR-PROPOSAL-NOT-PASSED (err u607))
(define-constant ERR-ALREADY-EXECUTED (err u608))
(define-constant ERR-INVALID-PARAMETER (err u609))

;; Contract constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant VOTING-PERIOD u1008) ;; ~1 week in blocks (144 blocks/day)
(define-constant MIN-PROPOSAL-STAKE u1000000) ;; 1 STX minimum stake to create proposal
(define-constant QUORUM-THRESHOLD u30) ;; 30% of total voting power needed
(define-constant APPROVAL-THRESHOLD u51) ;; 51% approval needed to pass

;; ===================
;; DATA VARIABLES
;; ===================

;; Global governance state
(define-data-var proposal-id-nonce uint u0)
(define-data-var total-voting-power uint u0)
(define-data-var governance-active bool true)

;; Protocol parameters that can be changed via governance
(define-data-var protocol-interest-rate uint u500) ;; 5% (500 basis points)
(define-data-var protocol-collateral-ratio uint u150) ;; 150%
(define-data-var protocol-liquidation-threshold uint u120) ;; 120%

;; ===================
;; DATA MAPS
;; ===================

;; Governance token balances (voting power)
(define-map voting-power
    { user: principal }
    { power: uint }
)

;; Proposal details
(define-map proposals
    { proposal-id: uint }
    {
        proposer: principal,
        title: (string-ascii 50),
        description: (string-ascii 500),
        parameter-type: (string-ascii 20), ;; "interest-rate", "collateral-ratio", "liquidation-threshold"
        new-value: uint,
        votes-for: uint,
        votes-against: uint,
        start-block: uint,
        end-block: uint,
        executed: bool,
        proposer-stake: uint
    }
)

;; Track user votes on proposals
(define-map user-votes
    { proposal-id: uint, voter: principal }
    { 
        vote: bool, ;; true = for, false = against
        voting-power: uint
    }
)

;; Staked amounts for voting power
(define-map user-stakes
    { user: principal }
    { 
        staked-amount: uint,
        last-stake-block: uint
    }
)

;; ===================
;; PRIVATE FUNCTIONS
;; ===================

;; Helper function to get minimum of two values
(define-private (min-uint (a uint) (b uint))
    (if (<= a b) a b)
)

;; Get next proposal ID
(define-private (get-next-proposal-id)
    (let (
        (current-id (var-get proposal-id-nonce))
        (next-id (+ current-id u1))
    )
    (var-set proposal-id-nonce next-id)
    next-id)
)

;; Calculate voting power based on stake and time
(define-private (calculate-voting-power (staked-amount uint) (blocks-staked uint))
    (let (
        (base-power staked-amount)
        (time-multiplier (min-uint (/ blocks-staked u144) u10)) ;; Max 10x multiplier after 10 days
    )
    (+ base-power (/ (* base-power time-multiplier) u10)))
)

;; Check if proposal meets quorum
(define-private (meets-quorum (total-votes uint))
    (let (
        (required-votes (/ (* (var-get total-voting-power) QUORUM-THRESHOLD) u100))
    )
    (>= total-votes required-votes))
)

;; Check if proposal is approved
(define-private (is-approved (votes-for uint) (votes-against uint))
    (let (
        (total-votes (+ votes-for votes-against))
        (approval-votes (/ (* total-votes APPROVAL-THRESHOLD) u100))
    )
    (>= votes-for approval-votes))
)

;; ===================
;; PUBLIC FUNCTIONS
;; ===================

;; Stake STX to gain voting power
(define-public (stake-for-voting (amount uint))
    (let (
        (sender tx-sender)
        (current-stake (default-to { staked-amount: u0, last-stake-block: block-height } 
                       (map-get? user-stakes { user: sender })))
        (current-amount (get staked-amount current-stake))
        (last-stake-block (get last-stake-block current-stake))
        (new-total-amount (+ current-amount amount))
    )
    (asserts! (> amount u0) ERR-INVALID-PARAMETER)
    (asserts! (var-get governance-active) ERR-UNAUTHORIZED)
    
    ;; Transfer STX from user to contract
    (try! (stx-transfer? amount sender (as-contract tx-sender)))
    
    ;; Update user stake
    (map-set user-stakes 
        { user: sender }
        { 
            staked-amount: new-total-amount,
            last-stake-block: block-height
        }
    )
    
    ;; Calculate and update voting power
    (let (
        (blocks-staked (- block-height last-stake-block))
        (new-voting-power (calculate-voting-power new-total-amount blocks-staked))
        (old-voting-power (default-to { power: u0 } (map-get? voting-power { user: sender })))
        (old-power (get power old-voting-power))
    )
    (map-set voting-power { user: sender } { power: new-voting-power })
    (var-set total-voting-power (+ (- (var-get total-voting-power) old-power) new-voting-power))
    )
    
    (ok { staked: amount, new-total-stake: new-total-amount })
    )
)

;; Unstake STX (removes voting power)
(define-public (unstake-voting-power (amount uint))
    (let (
        (sender tx-sender)
        (current-stake (unwrap! (map-get? user-stakes { user: sender }) ERR-UNAUTHORIZED))
        (staked-amount (get staked-amount current-stake))
        (remaining-stake (- staked-amount amount))
    )
    (asserts! (> amount u0) ERR-INVALID-PARAMETER)
    (asserts! (>= staked-amount amount) ERR-INSUFFICIENT-STAKE)
    
    ;; Transfer STX from contract to user
    (try! (as-contract (stx-transfer? amount tx-sender sender)))
    
    ;; Update user stake
    (if (> remaining-stake u0)
        (map-set user-stakes 
            { user: sender }
            (merge current-stake { staked-amount: remaining-stake })
        )
        (map-delete user-stakes { user: sender })
    )
    
    ;; Update voting power
    (let (
        (old-power (default-to u0 (get power (map-get? voting-power { user: sender }))))
        (new-power (if (> remaining-stake u0) 
                      (calculate-voting-power remaining-stake u0)
                      u0))
    )
    (if (> new-power u0)
        (map-set voting-power { user: sender } { power: new-power })
        (map-delete voting-power { user: sender })
    )
    (var-set total-voting-power (+ (- (var-get total-voting-power) old-power) new-power))
    )
    
    (ok { unstaked: amount, remaining-stake: remaining-stake })
    )
)

;; Create a governance proposal
(define-public (create-proposal 
    (title (string-ascii 50)) 
    (description (string-ascii 500))
    (parameter-type (string-ascii 20))
    (new-value uint))
    (let (
        (sender tx-sender)
        (proposal-id (get-next-proposal-id))
        (user-power (default-to u0 (get power (map-get? voting-power { user: sender }))))
    )
    (asserts! (>= user-power MIN-PROPOSAL-STAKE) ERR-INSUFFICIENT-STAKE)
    (asserts! (var-get governance-active) ERR-UNAUTHORIZED)
    (asserts! (> new-value u0) ERR-INVALID-PARAMETER)
    
    ;; Validate parameter type
    (asserts! (or (is-eq parameter-type "interest-rate")
                  (or (is-eq parameter-type "collateral-ratio")
                      (is-eq parameter-type "liquidation-threshold"))) ERR-INVALID-PARAMETER)
    
    ;; Create proposal
    (map-set proposals
        { proposal-id: proposal-id }
        {
            proposer: sender,
            title: title,
            description: description,
            parameter-type: parameter-type,
            new-value: new-value,
            votes-for: u0,
            votes-against: u0,
            start-block: block-height,
            end-block: (+ block-height VOTING-PERIOD),
            executed: false,
            proposer-stake: MIN-PROPOSAL-STAKE
        }
    )
    
    (ok { proposal-id: proposal-id, voting-ends: (+ block-height VOTING-PERIOD) })
    )
)

;; Vote on a proposal
(define-public (vote-on-proposal (proposal-id uint) (vote-for bool))
    (let (
        (sender tx-sender)
        (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) ERR-PROPOSAL-NOT-FOUND))
        (user-power (default-to u0 (get power (map-get? voting-power { user: sender }))))
        (end-block (get end-block proposal))
        (votes-for (get votes-for proposal))
        (votes-against (get votes-against proposal))
    )
    (asserts! (> user-power u0) ERR-INSUFFICIENT-STAKE)
    (asserts! (<= block-height end-block) ERR-VOTING-PERIOD-ENDED)
    (asserts! (is-none (map-get? user-votes { proposal-id: proposal-id, voter: sender })) ERR-ALREADY-VOTED)
    
    ;; Record vote
    (map-set user-votes
        { proposal-id: proposal-id, voter: sender }
        { 
            vote: vote-for,
            voting-power: user-power
        }
    )
    
    ;; Update proposal vote counts
    (map-set proposals
        { proposal-id: proposal-id }
        (merge proposal {
            votes-for: (if vote-for (+ votes-for user-power) votes-for),
            votes-against: (if vote-for votes-against (+ votes-against user-power))
        })
    )
    
    (ok { voted-for: vote-for, voting-power-used: user-power })
    )
)

;; Execute a passed proposal
(define-public (execute-proposal (proposal-id uint))
    (let (
        (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) ERR-PROPOSAL-NOT-FOUND))
        (end-block (get end-block proposal))
        (votes-for (get votes-for proposal))
        (votes-against (get votes-against proposal))
        (total-votes (+ votes-for votes-against))
        (executed (get executed proposal))
        (parameter-type (get parameter-type proposal))
        (new-value (get new-value proposal))
    )
    (asserts! (> block-height end-block) ERR-VOTING-PERIOD-ACTIVE)
    (asserts! (not executed) ERR-ALREADY-EXECUTED)
    (asserts! (meets-quorum total-votes) ERR-PROPOSAL-NOT-PASSED)
    (asserts! (is-approved votes-for votes-against) ERR-PROPOSAL-NOT-PASSED)
    
    ;; Execute the proposal by updating the relevant parameter
    (if (is-eq parameter-type "interest-rate")
        (var-set protocol-interest-rate new-value)
        (if (is-eq parameter-type "collateral-ratio")
            (var-set protocol-collateral-ratio new-value)
            (var-set protocol-liquidation-threshold new-value)
        )
    )
    
    ;; Mark proposal as executed
    (map-set proposals
        { proposal-id: proposal-id }
        (merge proposal { executed: true })
    )
    
    (ok { 
        proposal-id: proposal-id, 
        parameter-changed: parameter-type,
        new-value: new-value 
    })
    )
)

;; ===================
;; READ-ONLY FUNCTIONS
;; ===================

;; Get user's voting power
(define-read-only (get-voting-power (user principal))
    (default-to { power: u0 } (map-get? voting-power { user: user }))
)

;; Get user's stake information
(define-read-only (get-user-stake (user principal))
    (default-to { staked-amount: u0, last-stake-block: u0 } (map-get? user-stakes { user: user }))
)

;; Get proposal details
(define-read-only (get-proposal (proposal-id uint))
    (map-get? proposals { proposal-id: proposal-id })
)

;; Get user's vote on a proposal
(define-read-only (get-user-vote (proposal-id uint) (voter principal))
    (map-get? user-votes { proposal-id: proposal-id, voter: voter })
)

;; Get current protocol parameters
(define-read-only (get-protocol-parameters)
    {
        interest-rate: (var-get protocol-interest-rate),
        collateral-ratio: (var-get protocol-collateral-ratio),
        liquidation-threshold: (var-get protocol-liquidation-threshold)
    }
)

;; Get governance statistics
(define-read-only (get-governance-stats)
    {
        total-proposals: (var-get proposal-id-nonce),
        total-voting-power: (var-get total-voting-power),
        governance-active: (var-get governance-active),
        contract-balance: (stx-get-balance (as-contract tx-sender))
    }
)

;; Check if proposal can be executed
(define-read-only (can-execute-proposal (proposal-id uint))
    (let (
        (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) (ok false)))
        (end-block (get end-block proposal))
        (votes-for (get votes-for proposal))
        (votes-against (get votes-against proposal))
        (total-votes (+ votes-for votes-against))
        (executed (get executed proposal))
    )
    (ok (and 
        (> block-height end-block)
        (not executed)
        (meets-quorum total-votes)
        (is-approved votes-for votes-against)
    )))
)

;; ===================
;; ADMIN FUNCTIONS
;; ===================

;; Emergency pause governance (owner only)
(define-public (pause-governance)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (var-set governance-active false)
        (ok true)
    )
)

(define-public (unpause-governance)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (var-set governance-active true)
        (ok true)
    )
)
