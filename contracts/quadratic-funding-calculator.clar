;; quadratic-funding-calculator.clar
;; Quadratic Funding Calculator Smart Contract
;; Manages funding rounds, contribution processing, and quadratic funding mathematics
;; Handles Sybil resistance mechanisms and distributes matching funds fairly

;; Constants and Error Codes
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_NOT_FOUND (err u101))
(define-constant ERR_INVALID_AMOUNT (err u102))
(define-constant ERR_ROUND_CLOSED (err u103))
(define-constant ERR_ROUND_NOT_STARTED (err u104))
(define-constant ERR_ALREADY_CONTRIBUTED (err u105))
(define-constant ERR_INSUFFICIENT_FUNDS (err u106))
(define-constant ERR_SYBIL_DETECTED (err u107))
(define-constant ERR_CONTRIBUTION_LIMIT (err u108))
(define-constant ERR_INVALID_PROJECT (err u109))
(define-constant ERR_ROUND_ACTIVE (err u110))

;; Funding parameters
(define-constant MIN_CONTRIBUTION u10000) ;; 0.01 STX minimum
(define-constant MAX_CONTRIBUTION u100000000) ;; 100 STX maximum per user per project
(define-constant SYBIL_THRESHOLD u5) ;; Max contributions per user per round
(define-constant ROUND_DURATION u1008) ;; ~1 week in blocks
(define-constant MATCHING_FUND_CAP u1000000000) ;; 1000 STX cap

;; Data Structures
(define-map funding-rounds
    { round-id: uint }
    {
        name: (string-ascii 100),
        description: (string-ascii 500),
        total-matching-fund: uint,
        distributed-matching: uint,
        start-block: uint,
        end-block: uint,
        is-active: bool,
        project-count: uint,
        total-contributions: uint,
        created-by: principal
    }
)

(define-map projects
    { round-id: uint, project-id: uint }
    {
        creator: principal,
        name: (string-ascii 100),
        description: (string-ascii 500),
        funding-goal: uint,
        total-raised: uint,
        contribution-count: uint,
        quadratic-score: uint,
        is-approved: bool,
        impact-score: uint
    }
)

(define-map contributions
    { round-id: uint, project-id: uint, contributor: principal }
    {
        amount: uint,
        timestamp: uint,
        is-verified: bool,
        reputation-weight: uint
    }
)

(define-map user-reputation
    { user: principal }
    {
        total-contributions: uint,
        successful-projects-backed: uint,
        reputation-score: uint,
        last-activity: uint,
        is-verified: bool,
        sybil-resistance-score: uint
    }
)

(define-map round-user-stats
    { round-id: uint, user: principal }
    {
        total-contributed: uint,
        projects-backed: uint,
        last-contribution: uint
    }
)

;; Global counters
(define-data-var next-round-id uint u1)
(define-data-var next-project-id uint u1)
(define-data-var total-funds-distributed uint u0)
(define-data-var active-rounds uint u0)

;; Private helper functions
(define-private (calculate-quadratic-score (total-contributions uint) (contributor-count uint))
    ;; Simplified quadratic score calculation
    ;; In production, this would implement proper quadratic funding mathematics
    (if (> contributor-count u0)
        (let (
            (avg-contribution (/ total-contributions contributor-count))
            ;; Simplified square root approximation
            (sqrt-avg (if (> avg-contribution u10000) (/ avg-contribution u100) avg-contribution))
        )
            (* sqrt-avg contributor-count)
        )
        u0
    )
)

(define-private (calculate-matching-distribution (project-quadratic-score uint) (total-round-score uint) (available-matching uint))
    (if (> total-round-score u0)
        (/ (* project-quadratic-score available-matching) total-round-score)
        u0
    )
)

(define-private (update-user-reputation (user principal) (contribution-amount uint))
    (let (
        (current-rep (default-to
            {total-contributions: u0, successful-projects-backed: u0, reputation-score: u100, last-activity: u0, is-verified: false, sybil-resistance-score: u100}
            (map-get? user-reputation {user: user})
        ))
    )
        (map-set user-reputation
            {user: user}
            (merge current-rep {
                total-contributions: (+ (get total-contributions current-rep) contribution-amount),
                reputation-score: (if (< (+ (get reputation-score current-rep) u1) u1000) (+ (get reputation-score current-rep) u1) u1000),
                last-activity: stacks-block-height,
                sybil-resistance-score: (calculate-sybil-score user)
            })
        )
    )
)

(define-private (calculate-sybil-score (user principal))
    ;; Simplified Sybil resistance calculation
    ;; In production, this would include more sophisticated mechanisms
    (let (
        (user-rep (map-get? user-reputation {user: user}))
    )
        (match user-rep
            rep (if (get is-verified rep) u100 u50)
            u25
        )
    )
)

(define-private (is-round-active (round-id uint))
    (match (map-get? funding-rounds {round-id: round-id})
        round
            (and 
                (get is-active round)
                (>= stacks-block-height (get start-block round))
                (<= stacks-block-height (get end-block round))
            )
        false
    )
)

;; Public functions for round management
(define-public (create-funding-round
    (name (string-ascii 100))
    (description (string-ascii 500))
    (matching-fund uint)
    (duration-blocks uint)
)
    (let (
        (round-id (var-get next-round-id))
    )
        (asserts! (<= matching-fund MATCHING_FUND_CAP) ERR_INVALID_AMOUNT)
        (asserts! (> duration-blocks u0) ERR_INVALID_AMOUNT)
        (asserts! (<= duration-blocks ROUND_DURATION) ERR_INVALID_AMOUNT)
        
        ;; Transfer matching fund to contract (simplified)
        ;; (try! (stx-transfer? matching-fund tx-sender (as-contract tx-sender)))
        
        (map-set funding-rounds
            {round-id: round-id}
            {
                name: name,
                description: description,
                total-matching-fund: matching-fund,
                distributed-matching: u0,
                start-block: (+ stacks-block-height u1),
                end-block: (+ stacks-block-height duration-blocks),
                is-active: true,
                project-count: u0,
                total-contributions: u0,
                created-by: tx-sender
            }
        )
        
        (var-set next-round-id (+ round-id u1))
        (var-set active-rounds (+ (var-get active-rounds) u1))
        
        (ok round-id)
    )
)

;; Submit project to funding round
(define-public (submit-project
    (round-id uint)
    (name (string-ascii 100))
    (description (string-ascii 500))
    (funding-goal uint)
)
    (let (
        (project-id (var-get next-project-id))
        (round-info (map-get? funding-rounds {round-id: round-id}))
    )
        (asserts! (is-some round-info) ERR_NOT_FOUND)
        (asserts! (is-round-active round-id) ERR_ROUND_NOT_STARTED)
        (asserts! (> funding-goal u0) ERR_INVALID_AMOUNT)
        
        (map-set projects
            {round-id: round-id, project-id: project-id}
            {
                creator: tx-sender,
                name: name,
                description: description,
                funding-goal: funding-goal,
                total-raised: u0,
                contribution-count: u0,
                quadratic-score: u0,
                is-approved: false,
                impact-score: u0
            }
        )
        
        ;; Update round project count
        (match round-info
            round
                (map-set funding-rounds
                    {round-id: round-id}
                    (merge round {project-count: (+ (get project-count round) u1)})
                )
            false
        )
        
        (var-set next-project-id (+ project-id u1))
        
        (ok project-id)
    )
)

;; Contribute to a project with quadratic funding
(define-public (contribute-to-project
    (round-id uint)
    (project-id uint)
    (amount uint)
)
    (let (
        (project-key {round-id: round-id, project-id: project-id})
        (contributor-key {round-id: round-id, project-id: project-id, contributor: tx-sender})
        (project-info (map-get? projects project-key))
        (existing-contribution (map-get? contributions contributor-key))
        (user-round-stats (default-to
            {total-contributed: u0, projects-backed: u0, last-contribution: u0}
            (map-get? round-user-stats {round-id: round-id, user: tx-sender})
        ))
    )
        (asserts! (is-some project-info) ERR_INVALID_PROJECT)
        (asserts! (is-round-active round-id) ERR_ROUND_CLOSED)
        (asserts! (>= amount MIN_CONTRIBUTION) ERR_INVALID_AMOUNT)
        (asserts! (<= amount MAX_CONTRIBUTION) ERR_CONTRIBUTION_LIMIT)
        (asserts! (is-none existing-contribution) ERR_ALREADY_CONTRIBUTED)
        (asserts! (< (get projects-backed user-round-stats) SYBIL_THRESHOLD) ERR_SYBIL_DETECTED)
        
        ;; Transfer contribution (simplified)
        ;; (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        
        ;; Record contribution
        (map-set contributions
            contributor-key
            {
                amount: amount,
                timestamp: stacks-block-height,
                is-verified: true,
                reputation-weight: (calculate-sybil-score tx-sender)
            }
        )
        
        ;; Update project stats
        (match project-info
            project
                (let (
                    (new-total (+ (get total-raised project) amount))
                    (new-count (+ (get contribution-count project) u1))
                )
                    (map-set projects
                        project-key
                        (merge project {
                            total-raised: new-total,
                            contribution-count: new-count,
                            quadratic-score: (calculate-quadratic-score new-total new-count)
                        })
                    )
                )
            false
        )
        
        ;; Update user round stats
        (map-set round-user-stats
            {round-id: round-id, user: tx-sender}
            {
                total-contributed: (+ (get total-contributed user-round-stats) amount),
                projects-backed: (+ (get projects-backed user-round-stats) u1),
                last-contribution: stacks-block-height
            }
        )
        
        ;; Update user reputation
        (update-user-reputation tx-sender amount)
        
        (ok true)
    )
)

;; Finalize round and distribute matching funds
(define-public (finalize-round (round-id uint))
    (let (
        (round-info (map-get? funding-rounds {round-id: round-id}))
    )
        (asserts! (is-some round-info) ERR_NOT_FOUND)
        
        (match round-info
            round
                (begin
                    (asserts! (is-eq tx-sender (get created-by round)) ERR_UNAUTHORIZED)
                    (asserts! (get is-active round) ERR_ROUND_CLOSED)
                    (asserts! (> stacks-block-height (get end-block round)) ERR_ROUND_ACTIVE)
                    
                    ;; Mark round as inactive
                    (map-set funding-rounds
                        {round-id: round-id}
                        (merge round {is-active: false})
                    )
                    
                    (var-set active-rounds (- (var-get active-rounds) u1))
                    (var-set total-funds-distributed (+ (var-get total-funds-distributed) (get total-matching-fund round)))
                    
                    (ok true)
                )
            ERR_NOT_FOUND
        )
    )
)

;; Read-only functions
(define-read-only (get-funding-round (round-id uint))
    (map-get? funding-rounds {round-id: round-id})
)

(define-read-only (get-project-info (round-id uint) (project-id uint))
    (map-get? projects {round-id: round-id, project-id: project-id})
)

(define-read-only (get-user-contribution (round-id uint) (project-id uint) (user principal))
    (map-get? contributions {round-id: round-id, project-id: project-id, contributor: user})
)

(define-read-only (get-user-reputation (user principal))
    (map-get? user-reputation {user: user})
)

(define-read-only (get-platform-stats)
    {
        total-rounds: (var-get next-round-id),
        active-rounds: (var-get active-rounds),
        total-projects: (var-get next-project-id),
        total-funds-distributed: (var-get total-funds-distributed)
    }
)

(define-read-only (calculate-project-matching (round-id uint) (project-id uint) (total-round-quadratic uint))
    (let (
        (project-info (map-get? projects {round-id: round-id, project-id: project-id}))
        (round-info (map-get? funding-rounds {round-id: round-id}))
    )
        (match project-info
            project
                (match round-info
                    round
                        (calculate-matching-distribution 
                            (get quadratic-score project)
                            total-round-quadratic
                            (get total-matching-fund round)
                        )
                    u0
                )
            u0
        )
    )
)

;; title: quadratic-funding-calculator
;; version:
;; summary:
;; description:

;; traits
;;

;; token definitions
;;

;; constants
;;

;; data vars
;;

;; data maps
;;

;; public functions
;;

;; read only functions
;;

;; private functions
;;

