;; Enhanced Governance Contract for Simple Lending Platform
;; Allows platform users to propose and vote on protocol changes with improved security

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
(define-constant ERR-GOVERNANCE-PAUSED (err u610))
(define-constant ERR-PROPOSAL-EXPIRED (err u611))
(define-constant ERR-INVALID-LENDING-CONTRACT (err u612))
(define-constant ERR-EXECUTION-FAILED (err u613))

;; Contract constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant VOTING-PERIOD u1008) ;; ~1 week in blocks (144 blocks/day)
(define-constant MIN-PROPOSAL-STAKE u1000000) ;; 1 STX minimum stake to create proposal
(define-constant QUORUM-THRESHOLD u30) ;; 30% of total voting power needed
(define-constant APPROVAL-THRESHOLD u51) ;; 51% approval needed to pass
(define-constant MAX-PROPOSAL-LIFETIME u2016) ;; 2 weeks max lifetime for proposals
(define-constant DELEGATION-DECAY-BLOCKS u1440) ;; 10 days before delegation expires
(define-constant MIN-VOTING-POWER u100000) ;; 0.1 STX minimum to vote

;; ===================
;; DATA VARIABLES
;; ===================

;; Global governance state
(define-data-var proposal-id-nonce uint u0)
(define-data-var total-voting-power uint u0)
(define-data-var governance-active bool true)
(define-data-var lending-contract (optional principal) none)
(define-data-var total-staked uint u0)

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
    { 
        power: uint,
        last-update: uint
    }
)

;; Voting delegation
(define-map delegations
    { delegator: principal }
    { 
        delegate: principal,
        delegation-block: uint,
        voting-power-delegated: uint
    }
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
        execution-deadline: uint,
        executed: bool,
        proposer-stake: uint,
        total-voters: uint
    }
)

;; Track user votes on proposals
(define-map user-votes
    { proposal-id: uint, voter: principal }
    { 
        vote: bool, ;; true = for, false = against
        voting-power: uint,
        vote-block: uint
    }
)

;; Staked amounts for voting power
(define-map user-stakes
    { user: principal }
    { 
        staked-amount: uint,
        last-stake-block: uint,
        lock-end-block: uint
    }
)

;; Proposal execution history
(define-map execution-history
    { proposal-id: uint }
    {
        execution-block: uint,
        executor: principal,
        old-value: uint,
        new-value: uint
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

;; Check if delegation is still valid
(define-private (is-delegation-valid (delegation-block uint))
    (<= (- block-height delegation-block) DELEGATION-DECAY-BLOCKS)
)

;; Get effective voting power (including delegations)
(define-private (get-effective-voting-power (user principal))
    (let (
        (base-power (default-to u0 (get power (map-get? voting-power { user: user }))))
        (delegation (map-get? delegations { delegator: user }))
    )
    (match delegation
        del-data (if (is-delegation-valid (get delegation-block del-data))
                    u0 ;; Power is delegated
                    base-power)
        base-power ;; No delegation
    ))
)

;; ===================
;; GOVERNANCE INTEGRATION
;; ===================

;; Set lending contract (owner only)
(define-public (set-lending-contract (lending-principal principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (var-set lending-contract (some lending-principal))
        (ok true)
    )
)

;; Execute parameter change on lending contract
(define-private (execute-parameter-change (parameter-type (string-ascii 20)) (new-value uint))
    (let (
        (lending-principal (unwrap! (var-get lending-contract) ERR-INVALID-LENDING-CONTRACT))
    )
    (if (is-eq parameter-type "interest-rate")
        (contract-call? .lending-platform update-interest-rate new-value)
        (if (is-eq parameter-type "collateral-ratio")
            (contract-call? .lending-platform update-collateral-ratio new-value)
            (ok new-value) ;; For liquidation-threshold, just update local var
        ))
    )
)

;; ===================
;; PUBLIC FUNCTIONS
;; ===================

;; Stake STX to gain voting power with optional lock period
(define-public (stake-for-voting (amount uint) (lock-blocks uint))
    (let (
        (sender tx-sender)
        (current-stake (default-to { staked-amount: u0, last-stake-block: block-height, lock-end-block: u0 } 
                       (map-get? user-stakes { user: sender })))
        (current-amount (get staked-amount current-stake))
        (last-stake-block (get last-stake-block current-stake))
        (new-total-amount (+ current-amount amount))
        (lock-end (+ block-height lock-blocks))
        (lock-bonus (/ lock-blocks u1440)) ;; Bonus for longer locks
    )
    (asserts! (> amount u0) ERR-INVALID-PARAMETER)
    (asserts! (var-get governance-active) ERR-GOVERNANCE-PAUSED)
    (asserts! (<= lock-blocks u14400) ERR-INVALID-PARAMETER) ;; Max 100 days lock
    
    ;; Transfer STX from user to contract
    (try! (stx-transfer? amount sender (as-contract tx-sender)))
    
    ;; Update user stake
    (map-set user-stakes 
        { user: sender }
        { 
            staked-amount: new-total-amount,
            last-stake-block: block-height,
            lock-end-block: (max-uint lock-end (get lock-end-block current-stake))
        }
    )
    
    ;; Calculate and update voting power
    (let (
        (blocks-staked (- block-height last-stake-block))
        (base-voting-power (calculate-voting-power new-total-amount blocks-staked))
        (lock-multiplier (+ u100 lock-bonus)) ;; Base 100% + lock bonus
        (new-voting-power (/ (* base-voting-power lock-multiplier) u100))
        (old-voting-power (default-to { power: u0, last-update: block-height } (map-get? voting-power { user: sender })))
        (old-power (get power old-voting-power))
    )
    (map-set voting-power 
        { user: sender } 
        { 
            power: new-voting-power,
            last-update: block-height
        })
    (var-set total-voting-power (+ (- (var-get total-voting-power) old-power) new-voting-power))
    (var-set total-staked (+ (var-get total-staked) amount))
    
    (ok { staked: amount, new-total-stake: new-total-amount, voting-power: new-voting-power })
    )
    )
)

;; Unstake STX (removes voting power) - respects lock period
(define-public (unstake-voting-power (amount uint))
    (let (
        (sender tx-sender)
        (current-stake (unwrap! (map-get? user-stakes { user: sender }) ERR-UNAUTHORIZED))
        (staked-amount (get staked-amount current-stake))
        (lock-end (get lock-end-block current-stake))
        (remaining-stake (- staked-amount amount))
    )
    (asserts! (> amount u0) ERR-INVALID-PARAMETER)
    (asserts! (>= staked-amount amount) ERR-INSUFFICIENT-STAKE)
    (asserts! (>= block-height lock-end) ERR-UNAUTHORIZED) ;; Check lock period
    
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
        (map-set voting-power 
            { user: sender } 
            { 
                power: new-power,
                last-update: block-height
            })
        (map-delete voting-power { user: sender })
    )
    (var-set total-voting-power (+ (- (var-get total-voting-power) old-power) new-power))
    (var-set total-staked (- (var-get total-staked) amount))
    )
    
    (ok { unstaked: amount, remaining-stake: remaining-stake })
    )
)

;; Delegate voting power to another user
(define-public (delegate-voting-power (delegate principal))
    (let (
        (sender tx-sender)
        (sender-power (get-effective-voting-power sender))
        (current-delegation (map-get? delegations { delegator: sender }))
    )
    (asserts! (> sender-power u0) ERR-INSUFFICIENT-STAKE)
    (asserts! (not (is-eq sender delegate)) ERR-INVALID-PARAMETER)
    (asserts! (var-get governance-active) ERR-GOVERNANCE-PAUSED)
    
    ;; Remove old delegation if exists
    (match current-delegation
        old-del (let (
                    (old-delegate (get delegate old-del))
                    (old-power (get voting-power-delegated old-del))
                    (old-delegate-power (default-to { power: u0, last-update: block-height } 
                                       (map-get? voting-power { user: old-delegate })))
                )
                (map-set voting-power 
                    { user: old-delegate }
                    (merge old-delegate-power { power: (- (get power old-delegate-power) old-power) }))
                )
        true
    )
    
    ;; Create new delegation
    (map-set delegations
        { delegator: sender }
        {
            delegate: delegate,
            delegation-block: block-height,
            voting-power-delegated: sender-power
        }
    )
    
    ;; Add power to delegate
    (let (
        (delegate-power (default-to { power: u0, last-update: block-height } (map-get? voting-power { user: delegate })))
    )
    (map-set voting-power 
        { user: delegate }
        (merge delegate-power { power: (+ (get power delegate-power) sender-power) }))
    )
    
    (ok { delegated-to: delegate, voting-power-delegated: sender-power })
    )
)

;; Revoke voting power delegation
(define-public (revoke-delegation)
    (let (
        (sender tx-sender)
        (delegation (unwrap! (map-get? delegations { delegator: sender }) ERR-UNAUTHORIZED))
        (delegate (get delegate delegation))
        (delegated-power (get voting-power-delegated delegation))
        (delegate-power (default-to { power: u0, last-update: block-height } (map-get? voting-power { user: delegate })))
    )
    ;; Remove power from delegate
    (map-set voting-power 
        { user: delegate }
        (merge delegate-power { power: (- (get power delegate-power) delegated-power) }))
    
    ;; Remove delegation
    (map-delete delegations { delegator: sender })
    
    (ok { revoked-from: delegate, voting-power-returned: delegated-power })
    )
)

;; Create a governance proposal with enhanced validation
(define-public (create-proposal 
    (title (string-ascii 50)) 
    (description (string-ascii 500))
    (parameter-type (string-ascii 20))
    (new-value uint))
    (let (
        (sender tx-sender)
        (proposal-id (get-next-proposal-id))
        (user-power (get-effective-voting-power sender))
        (execution-deadline (+ block-height MAX-PROPOSAL-LIFETIME))
    )
    (asserts! (>= user-power MIN-PROPOSAL-STAKE) ERR-INSUFFICIENT-STAKE)
    (asserts! (var-get governance-active) ERR-GOVERNANCE-PAUSED)
    (asserts! (> new-value u0) ERR-INVALID-PARAMETER)
    
    ;; Enhanced parameter validation
    (asserts! (or (is-eq parameter-type "interest-rate")
                  (or (is-eq parameter-type "collateral-ratio")
                      (is-eq parameter-type "liquidation-threshold"))) ERR-INVALID-PARAMETER)
    
    ;; Validate parameter ranges
    (if (is-eq parameter-type "interest-rate")
        (asserts! (and (>= new-value u100) (<= new-value u2000)) ERR-INVALID-PARAMETER) ;; 1% to 20%
        (if (is-eq parameter-type "collateral-ratio")
            (asserts! (and (>= new-value u110) (<= new-value u300)) ERR-INVALID-PARAMETER) ;; 110% to 300%
            (asserts! (and (>= new-value u105) (<= new-value u200)) ERR-INVALID-PARAMETER) ;; 105% to 200%
        )
    )
    
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
            execution-deadline: execution-deadline,
            executed: false,
            proposer-stake: MIN-PROPOSAL-STAKE,
            total-voters: u0
        }
    )
    
    (ok { proposal-id: proposal-id, voting-ends: (+ block-height VOTING-PERIOD), execution-deadline: execution-deadline })
    )
)

;; Vote on a proposal with delegation support
(define-public (vote-on-proposal (proposal-id uint) (vote-for bool))
    (let (
        (sender tx-sender)
        (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) ERR-PROPOSAL-NOT-FOUND))
        (user-power (get-effective-voting-power sender))
        (end-block (get end-block proposal))
        (votes-for (get votes-for proposal))
        (votes-against (get votes-against proposal))
        (total-voters (get total-voters proposal))
    )
    (asserts! (>= user-power MIN-VOTING-POWER) ERR-INSUFFICIENT-STAKE)
    (asserts! (<= block-height end-block) ERR-VOTING-PERIOD-ENDED)
    (asserts! (is-none (map-get? user-votes { proposal-id: proposal-id, voter: sender })) ERR-ALREADY-VOTED)
    (asserts! (var-get governance-active) ERR-GOVERNANCE-PAUSED)
    
    ;; Record vote
    (map-set user-votes
        { proposal-id: proposal-id, voter: sender }
        { 
            vote: vote-for,
            voting-power: user-power,
            vote-block: block-height
        }
    )
    
    ;; Update proposal vote counts
    (map-set proposals
        { proposal-id: proposal-id }
        (merge proposal {
            votes-for: (if vote-for (+ votes-for user-power) votes-for),
            votes-against: (if vote-for votes-against (+ votes-against user-power)),
            total-voters: (+ total-voters u1)
        })
    )
    
    (ok { voted-for: vote-for, voting-power-used: user-power })
    )
)

;; Execute a passed proposal with improved security
(define-public (execute-proposal (proposal-id uint))
    (let (
        (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) ERR-PROPOSAL-NOT-FOUND))
        (end-block (get end-block proposal))
        (execution-deadline (get execution-deadline proposal))
        (votes-for (get votes-for proposal))
        (votes-against (get votes-against proposal))
        (total-votes (+ votes-for votes-against))
        (executed (get executed proposal))
        (parameter-type (get parameter-type proposal))
        (new-value (get new-value proposal))
        (old-value (if (is-eq parameter-type "interest-rate")
                      (var-get protocol-interest-rate)
                      (if (is-eq parameter-type "collateral-ratio")
                          (var-get protocol-collateral-ratio)
                          (var-get protocol-liquidation-threshold))))
    )
    (asserts! (> block-height end-block) ERR-VOTING-PERIOD-ACTIVE)
    (asserts! (<= block-height execution-deadline) ERR-PROPOSAL-EXPIRED)
    (asserts! (not executed) ERR-ALREADY-EXECUTED)
    (asserts! (meets-quorum total-votes) ERR-PROPOSAL-NOT-PASSED)
    (asserts! (is-approved votes-for votes-against) ERR-PROPOSAL-NOT-PASSED)
    
    ;; Execute the proposal
    (if (is-eq parameter-type "liquidation-threshold")
        (begin
            (var-set protocol-liquidation-threshold new-value)
            new-value
        )
        (unwrap-panic (execute-parameter-change parameter-type new-value))
    )
    
    ;; Update local parameter tracking
    (if (is-eq parameter-type "interest-rate")
        (var-set protocol-interest-rate new-value)
        (if (is-eq parameter-type "collateral-ratio")
            (var-set protocol-collateral-ratio new-value)
            true
        )
    )
    
    ;; Mark proposal as executed
    (map-set proposals
        { proposal-id: proposal-id }
        (merge proposal { executed: true })
    )
    
    ;; Record execution history
    (map-set execution-history
        { proposal-id: proposal-id }
        {
            execution-block: block-height,
            executor: tx-sender,
            old-value: old-value,
            new-value: new-value
        }
    )
    
    (ok { 
        proposal-id: proposal-id, 
        parameter-changed: parameter-type,
        old-value: old-value,
        new-value: new-value 
    })
    )
)

;; ===================
;; READ-ONLY FUNCTIONS
;; ===================

;; Get user's voting power (including delegated power received)
(define-read-only (get-voting-power (user principal))
    (let (
        (base-power (default-to { power: u0, last-update: u0 } (map-get? voting-power { user: user })))
        (delegation (map-get? delegations { delegator: user }))
    )
    {
        base-power: (get power base-power),
        effective-power: (get-effective-voting-power user),
        is-delegated: (is-some delegation),
        last-update: (get last-update base-power)
    })
)

;; Get user's stake information
(define-read-only (get-user-stake (user principal))
    (let (
        (stake-info (default-to { staked-amount: u0, last-stake-block: u0, lock-end-block: u0 } 
                   (map-get? user-stakes { user: user })))
    )
    (merge stake-info {
        is-locked: (> (get lock-end-block stake-info) block-height),
        blocks-until-unlock: (max-uint u0 (- (get lock-end-block stake-info) block-height))
    }))
)

;; Get proposal details
(define-read-only (get-proposal (proposal-id uint))
    (let (
        (proposal (map-get? proposals { proposal-id: proposal-id }))
    )
    (match proposal
        prop-data (let (
                      (total-votes (+ (get votes-for prop-data) (get votes-against prop-data)))
                      (participation-rate (if (> (var-get total-voting-power) u0)
                                           (/ (* total-votes u100) (var-get total-voting-power))
                                           u0))
                  )
                  (some (merge prop-data {
                      total-votes: total-votes,
                      participation-rate: participation-rate,
                      meets-quorum: (meets-quorum total-votes),
                      is-approved: (is-approved (get votes-for prop-data) (get votes-against prop-data)),
                      can-execute: (and (> block-height (get end-block prop-data))
                                       (not (get executed prop-data))
                                       (meets-quorum total-votes)
                                       (is-approved (get votes-for prop-data) (get votes-against prop-data))
                                       (<= block-height (get execution-deadline prop-data))),
                      is-expired: (> block-height (get execution-deadline prop-data))
                  })))
        none
    ))
)

;; Get user's vote on a proposal
(define-read-only (get-user-vote (proposal-id uint) (voter principal))
    (map-get? user-votes { proposal-id: proposal-id, voter: voter })
)

;; Get delegation information
(define-read-only (get-delegation-info (user principal))
    (let (
        (delegation (map-get? delegations { delegator: user }))
    )
    (match delegation
        del-data (some (merge del-data {
                           is-active: (is-delegation-valid (get delegation-block del-data)),
                           blocks-remaining: (max-uint u0 (- DELEGATION-DECAY-BLOCKS (- block-height (get delegation-block del-data))))
                       }))
        none
    ))
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
        total-staked: (var-get total-staked),
        governance-active: (var-get governance-active),
        contract-balance: (stx-get-balance (as-contract tx-sender)),
        lending-contract: (var-get lending-contract)
    }
)

;; Get execution history for a proposal
(define-read-only (get-execution-history (proposal-id uint))
    (map-get? execution-history { proposal-id: proposal-id })
)

;; Check if proposal can be executed
(define-read-only (can-execute-proposal (proposal-id uint))
    (let (
        (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) (ok false)))
        (end-block (get end-block proposal))
        (execution-deadline (get execution-deadline proposal))
        (votes-for (get votes-for proposal))
        (votes-against (get votes-against proposal))
        (total-votes (+ votes-for votes-against))
        (executed (get executed proposal))
    )
    (ok (and 
        (> block-height end-block)
        (<= block-height execution-deadline)
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
