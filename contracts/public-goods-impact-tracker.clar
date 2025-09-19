;; public-goods-impact-tracker.clar
;; Public Goods Impact Tracker Smart Contract
;; Tracks funded project lifecycle, measures impact metrics, and manages community evaluation
;; Provides transparent reporting mechanisms and enables continuous improvement of funding criteria

;; Constants and Error Codes
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u200))
(define-constant ERR_NOT_FOUND (err u201))
(define-constant ERR_INVALID_MILESTONE (err u202))
(define-constant ERR_MILESTONE_NOT_DUE (err u203))
(define-constant ERR_ALREADY_SUBMITTED (err u204))
(define-constant ERR_INSUFFICIENT_EVIDENCE (err u205))
(define-constant ERR_EVALUATION_CLOSED (err u206))
(define-constant ERR_INVALID_SCORE (err u207))
(define-constant ERR_NOT_EVALUATOR (err u208))
(define-constant ERR_PROJECT_INACTIVE (err u209))
(define-constant ERR_INVALID_IMPACT_TYPE (err u210))

;; Impact tracking parameters
(define-constant MIN_EVIDENCE_LENGTH u50)
(define-constant MAX_EVIDENCE_LENGTH u1000)
(define-constant MIN_EVALUATORS u3)
(define-constant MAX_EVALUATORS u20)
(define-constant EVALUATION_PERIOD u144) ;; ~24 hours in blocks
(define-constant MILESTONE_GRACE_PERIOD u720) ;; ~5 days in blocks
(define-constant MIN_IMPACT_SCORE u0)
(define-constant MAX_IMPACT_SCORE u100)

;; Data structures for impact tracking
(define-map project-lifecycle
    { project-id: uint }
    {
        creator: principal,
        name: (string-ascii 100),
        description: (string-ascii 500),
        funding-received: uint,
        start-date: uint,
        expected-completion: uint,
        current-stage: (string-ascii 50),
        is-active: bool,
        total-milestones: uint,
        completed-milestones: uint,
        overall-impact-score: uint,
        community-rating: uint
    }
)

(define-map project-milestones
    { project-id: uint, milestone-id: uint }
    {
        title: (string-ascii 100),
        description: (string-ascii 500),
        due-date: uint,
        completion-date: uint,
        evidence-hash: (buff 64),
        evidence-description: (string-ascii 1000),
        is-completed: bool,
        verification-status: (string-ascii 20),
        impact-metrics: uint,
        evaluator-count: uint
    }
)

(define-map milestone-evaluations
    { project-id: uint, milestone-id: uint, evaluator: principal }
    {
        impact-score: uint,
        quality-score: uint,
        evidence-adequacy: uint,
        comments: (string-ascii 500),
        submitted-at: uint,
        evaluation-weight: uint
    }
)

(define-map impact-metrics
    { project-id: uint, metric-type: (string-ascii 50) }
    {
        baseline-value: uint,
        current-value: uint,
        target-value: uint,
        measurement-unit: (string-ascii 20),
        last-updated: uint,
        verification-method: (string-ascii 100),
        data-source: (string-ascii 200)
    }
)

(define-map evaluator-profiles
    { evaluator: principal }
    {
        total-evaluations: uint,
        accuracy-score: uint,
        expertise-areas: (list 5 (string-ascii 50)),
        reputation-score: uint,
        is-verified: bool,
        last-evaluation: uint
    }
)

(define-map community-feedback
    { project-id: uint, feedback-id: uint }
    {
        author: principal,
        feedback-type: (string-ascii 30),
        rating: uint,
        comments: (string-ascii 500),
        submitted-at: uint,
        is-verified: bool
    }
)

;; Global counters and tracking
(define-data-var next-milestone-id uint u1)
(define-data-var next-feedback-id uint u1)
(define-data-var total-projects-tracked uint u0)
(define-data-var total-completed-projects uint u0)
(define-data-var total-impact-assessments uint u0)

;; Private helper functions
(define-private (calculate-weighted-impact (project-id uint))
    (let (
        (project-info (map-get? project-lifecycle {project-id: project-id}))
    )
        (match project-info
            project
                (let (
                    (completion-ratio (if (> (get total-milestones project) u0)
                        (/ (* (get completed-milestones project) u100) (get total-milestones project))
                        u0))
                    (base-score (get overall-impact-score project))
                )
                    (/ (* base-score completion-ratio) u100)
                )
            u0
        )
    )
)

(define-private (update-evaluator-reputation (evaluator principal) (accuracy-bonus uint))
    (let (
        (current-profile (default-to
            {total-evaluations: u0, accuracy-score: u100, expertise-areas: (list), reputation-score: u100, is-verified: false, last-evaluation: u0}
            (map-get? evaluator-profiles {evaluator: evaluator})
        ))
    )
        (map-set evaluator-profiles
            {evaluator: evaluator}
            (merge current-profile {
                total-evaluations: (+ (get total-evaluations current-profile) u1),
                accuracy-score: (if (< (+ (get accuracy-score current-profile) accuracy-bonus) u1000) (+ (get accuracy-score current-profile) accuracy-bonus) u1000),
                reputation-score: (if (< (+ (get reputation-score current-profile) u1) u1000) (+ (get reputation-score current-profile) u1) u1000),
                last-evaluation: stacks-block-height
            })
        )
    )
)

(define-private (calculate-milestone-score (project-id uint) (milestone-id uint))
    (let (
        (evaluations (get-milestone-evaluations project-id milestone-id))
        (total-evaluators (len evaluations))
    )
        (if (> total-evaluators u0)
            (/ (fold + evaluations u0) total-evaluators)
            u0
        )
    )
)

(define-private (get-milestone-evaluations (project-id uint) (milestone-id uint))
    ;; Simplified - in production, this would aggregate all evaluator scores
    (list u85 u92 u78) ;; Mock evaluation scores
)

(define-private (is-milestone-due (project-id uint) (milestone-id uint))
    (match (map-get? project-milestones {project-id: project-id, milestone-id: milestone-id})
        milestone
            (<= (get due-date milestone) (+ stacks-block-height MILESTONE_GRACE_PERIOD))
        false
    )
)

;; Public functions for project tracking
(define-public (register-project
    (project-id uint)
    (name (string-ascii 100))
    (description (string-ascii 500))
    (funding-received uint)
    (completion-timeline uint)
)
    (let (
        (existing-project (map-get? project-lifecycle {project-id: project-id}))
    )
        (asserts! (is-none existing-project) ERR_ALREADY_SUBMITTED)
        (asserts! (> funding-received u0) ERR_INVALID_MILESTONE)
        (asserts! (> completion-timeline u0) ERR_INVALID_MILESTONE)
        
        (map-set project-lifecycle
            {project-id: project-id}
            {
                creator: tx-sender,
                name: name,
                description: description,
                funding-received: funding-received,
                start-date: stacks-block-height,
                expected-completion: (+ stacks-block-height completion-timeline),
                current-stage: "planning",
                is-active: true,
                total-milestones: u0,
                completed-milestones: u0,
                overall-impact-score: u0,
                community-rating: u0
            }
        )
        
        (var-set total-projects-tracked (+ (var-get total-projects-tracked) u1))
        
        (ok true)
    )
)

;; Add milestone to project
(define-public (add-milestone
    (project-id uint)
    (title (string-ascii 100))
    (description (string-ascii 500))
    (due-date uint)
)
    (let (
        (project-info (map-get? project-lifecycle {project-id: project-id}))
        (milestone-id (var-get next-milestone-id))
    )
        (asserts! (is-some project-info) ERR_NOT_FOUND)
        
        (match project-info
            project
                (begin
                    (asserts! (is-eq tx-sender (get creator project)) ERR_UNAUTHORIZED)
                    (asserts! (get is-active project) ERR_PROJECT_INACTIVE)
                    (asserts! (> due-date stacks-block-height) ERR_INVALID_MILESTONE)
                    
                    (map-set project-milestones
                        {project-id: project-id, milestone-id: milestone-id}
                        {
                            title: title,
                            description: description,
                            due-date: due-date,
                            completion-date: u0,
            evidence-hash: 0x,
                            evidence-description: "",
                            is-completed: false,
                            verification-status: "pending",
                            impact-metrics: u0,
                            evaluator-count: u0
                        }
                    )
                    
                    ;; Update project milestone count
                    (map-set project-lifecycle
                        {project-id: project-id}
                        (merge project {total-milestones: (+ (get total-milestones project) u1)})
                    )
                    
                    (var-set next-milestone-id (+ milestone-id u1))
                    
                    (ok milestone-id)
                )
            ERR_NOT_FOUND
        )
    )
)

;; Submit milestone completion evidence
(define-public (submit-milestone-evidence
    (project-id uint)
    (milestone-id uint)
    (evidence-hash (buff 64))
    (evidence-description (string-ascii 1000))
)
    (let (
        (milestone-info (map-get? project-milestones {project-id: project-id, milestone-id: milestone-id}))
        (project-info (map-get? project-lifecycle {project-id: project-id}))
    )
        (asserts! (is-some milestone-info) ERR_NOT_FOUND)
        (asserts! (is-some project-info) ERR_NOT_FOUND)
        
        (match milestone-info
            milestone
                (match project-info
                    project
                        (begin
                            (asserts! (is-eq tx-sender (get creator project)) ERR_UNAUTHORIZED)
                            (asserts! (not (get is-completed milestone)) ERR_ALREADY_SUBMITTED)
                            (asserts! (is-milestone-due project-id milestone-id) ERR_MILESTONE_NOT_DUE)
                            (asserts! (>= (len evidence-description) MIN_EVIDENCE_LENGTH) ERR_INSUFFICIENT_EVIDENCE)
                            (asserts! (<= (len evidence-description) MAX_EVIDENCE_LENGTH) ERR_INSUFFICIENT_EVIDENCE)
                            
                            (map-set project-milestones
                                {project-id: project-id, milestone-id: milestone-id}
                                (merge milestone {
                                    completion-date: stacks-block-height,
                                    evidence-hash: evidence-hash,
                                    evidence-description: evidence-description,
                                    verification-status: "under-review"
                                })
                            )
                            
                            (ok true)
                        )
                    ERR_NOT_FOUND
                )
            ERR_NOT_FOUND
        )
    )
)

;; Submit milestone evaluation
(define-public (evaluate-milestone
    (project-id uint)
    (milestone-id uint)
    (impact-score uint)
    (quality-score uint)
    (evidence-adequacy uint)
    (comments (string-ascii 500))
)
    (let (
        (milestone-info (map-get? project-milestones {project-id: project-id, milestone-id: milestone-id}))
        (existing-evaluation (map-get? milestone-evaluations {project-id: project-id, milestone-id: milestone-id, evaluator: tx-sender}))
    )
        (asserts! (is-some milestone-info) ERR_NOT_FOUND)
        (asserts! (is-none existing-evaluation) ERR_ALREADY_SUBMITTED)
        (asserts! (and (>= impact-score MIN_IMPACT_SCORE) (<= impact-score MAX_IMPACT_SCORE)) ERR_INVALID_SCORE)
        (asserts! (and (>= quality-score MIN_IMPACT_SCORE) (<= quality-score MAX_IMPACT_SCORE)) ERR_INVALID_SCORE)
        (asserts! (and (>= evidence-adequacy MIN_IMPACT_SCORE) (<= evidence-adequacy MAX_IMPACT_SCORE)) ERR_INVALID_SCORE)
        
        (match milestone-info
            milestone
                (begin
                    (asserts! (is-eq (get verification-status milestone) "under-review") ERR_EVALUATION_CLOSED)
                    
                    (map-set milestone-evaluations
                        {project-id: project-id, milestone-id: milestone-id, evaluator: tx-sender}
                        {
                            impact-score: impact-score,
                            quality-score: quality-score,
                            evidence-adequacy: evidence-adequacy,
                            comments: comments,
                            submitted-at: stacks-block-height,
                            evaluation-weight: u100
                        }
                    )
                    
                    ;; Update milestone evaluator count
                    (map-set project-milestones
                        {project-id: project-id, milestone-id: milestone-id}
                        (merge milestone {evaluator-count: (+ (get evaluator-count milestone) u1)})
                    )
                    
                    ;; Update evaluator reputation
                    (update-evaluator-reputation tx-sender u5)
                    
                    ;; Increment global assessment counter
                    (var-set total-impact-assessments (+ (var-get total-impact-assessments) u1))
                    
                    (ok true)
                )
            ERR_NOT_FOUND
        )
    )
)

;; Record impact metrics for a project
(define-public (record-impact-metric
    (project-id uint)
    (metric-type (string-ascii 50))
    (current-value uint)
    (target-value uint)
    (measurement-unit (string-ascii 20))
    (verification-method (string-ascii 100))
)
    (let (
        (project-info (map-get? project-lifecycle {project-id: project-id}))
        (existing-metric (map-get? impact-metrics {project-id: project-id, metric-type: metric-type}))
    )
        (asserts! (is-some project-info) ERR_NOT_FOUND)
        
        (match project-info
            project
                (begin
                    (asserts! (is-eq tx-sender (get creator project)) ERR_UNAUTHORIZED)
                    (asserts! (get is-active project) ERR_PROJECT_INACTIVE)
                    
                    (map-set impact-metrics
                        {project-id: project-id, metric-type: metric-type}
                        {
                            baseline-value: (match existing-metric metric (get baseline-value metric) current-value),
                            current-value: current-value,
                            target-value: target-value,
                            measurement-unit: measurement-unit,
                            last-updated: stacks-block-height,
                            verification-method: verification-method,
                            data-source: "project-creator"
                        }
                    )
                    
                    (ok true)
                )
            ERR_NOT_FOUND
        )
    )
)

;; Complete project and calculate final impact score
(define-public (finalize-project (project-id uint))
    (let (
        (project-info (map-get? project-lifecycle {project-id: project-id}))
    )
        (asserts! (is-some project-info) ERR_NOT_FOUND)
        
        (match project-info
            project
                (begin
                    (asserts! (is-eq tx-sender (get creator project)) ERR_UNAUTHORIZED)
                    (asserts! (get is-active project) ERR_PROJECT_INACTIVE)
                    (asserts! (>= (get completed-milestones project) (get total-milestones project)) ERR_INVALID_MILESTONE)
                    
                    (let (
                        (final-impact (calculate-weighted-impact project-id))
                    )
                        (map-set project-lifecycle
                            {project-id: project-id}
                            (merge project {
                                is-active: false,
                                current-stage: "completed",
                                overall-impact-score: final-impact
                            })
                        )
                        
                        (var-set total-completed-projects (+ (var-get total-completed-projects) u1))
                        
                        (ok final-impact)
                    )
                )
            ERR_NOT_FOUND
        )
    )
)

;; Read-only functions
(define-read-only (get-project-info (project-id uint))
    (map-get? project-lifecycle {project-id: project-id})
)

(define-read-only (get-milestone-info (project-id uint) (milestone-id uint))
    (map-get? project-milestones {project-id: project-id, milestone-id: milestone-id})
)

(define-read-only (get-impact-metric (project-id uint) (metric-type (string-ascii 50)))
    (map-get? impact-metrics {project-id: project-id, metric-type: metric-type})
)

(define-read-only (get-evaluator-profile (evaluator principal))
    (map-get? evaluator-profiles {evaluator: evaluator})
)

(define-read-only (get-platform-impact-stats)
    {
        total-projects: (var-get total-projects-tracked),
        completed-projects: (var-get total-completed-projects),
        total-assessments: (var-get total-impact-assessments),
        next-milestone-id: (var-get next-milestone-id),
        completion-rate: (if (> (var-get total-projects-tracked) u0)
            (/ (* (var-get total-completed-projects) u100) (var-get total-projects-tracked))
            u0)
    }
)

;; title: public-goods-impact-tracker
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

