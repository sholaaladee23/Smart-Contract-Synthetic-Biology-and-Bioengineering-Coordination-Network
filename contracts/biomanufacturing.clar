;; Biomanufacturing Optimization Contract
;; Uses engineered biology for sustainable production of materials

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-INPUT (err u101))
(define-constant ERR-NOT-FOUND (err u102))
(define-constant ERR-ALREADY-EXISTS (err u103))
(define-constant ERR-INSUFFICIENT-RESOURCES (err u106))

;; Data Variables
(define-data-var next-process-id uint u1)
(define-data-var next-batch-id uint u1)
(define-data-var optimization-enabled bool true)

;; Data Maps
(define-map manufacturing-processes
  { process-id: uint }
  {
    creator: principal,
    name: (string-ascii 64),
    target-material: (string-ascii 64),
    organism-strain: (string-ascii 64),
    efficiency-rating: uint,
    resource-requirements: uint,
    output-capacity: uint,
    status: (string-ascii 32),
    created-at: uint
  }
)

(define-map production-batches
  { batch-id: uint }
  {
    process-id: uint,
    operator: principal,
    start-time: uint,
    end-time: uint,
    input-resources: uint,
    actual-output: uint,
    quality-score: uint,
    efficiency-achieved: uint,
    status: (string-ascii 32)
  }
)

(define-map resource-allocations
  { process-id: uint, resource-type: (string-ascii 32) }
  {
    allocated-amount: uint,
    reserved-until: uint,
    allocator: principal
  }
)

(define-map optimization-parameters
  { process-id: uint }
  {
    temperature-range: { min: uint, max: uint },
    ph-range: { min: uint, max: uint },
    nutrient-concentration: uint,
    oxygen-level: uint,
    last-optimized: uint
  }
)

(define-map authorized-operators
  { operator: principal }
  { authorized: bool }
)

;; Authorization Functions
(define-private (is-contract-owner)
  (is-eq tx-sender CONTRACT-OWNER)
)

(define-private (is-authorized-operator)
  (default-to false (get authorized (map-get? authorized-operators { operator: tx-sender })))
)

;; Public Functions

;; Register a new manufacturing process
(define-public (register-process (name (string-ascii 64)) (target-material (string-ascii 64)) (organism-strain (string-ascii 64)) (resource-requirements uint) (output-capacity uint))
  (let
    (
      (process-id (var-get next-process-id))
    )
    (asserts! (> (len name) u0) ERR-INVALID-INPUT)
    (asserts! (> (len target-material) u0) ERR-INVALID-INPUT)
    (asserts! (> resource-requirements u0) ERR-INVALID-INPUT)
    (asserts! (> output-capacity u0) ERR-INVALID-INPUT)

    (map-set manufacturing-processes
      { process-id: process-id }
      {
        creator: tx-sender,
        name: name,
        target-material: target-material,
        organism-strain: organism-strain,
        efficiency-rating: u50,
        resource-requirements: resource-requirements,
        output-capacity: output-capacity,
        status: "registered",
        created-at: block-height
      }
    )

    (var-set next-process-id (+ process-id u1))
    (ok process-id)
  )
)

;; Start a production batch
(define-public (start-production-batch (process-id uint) (input-resources uint))
  (let
    (
      (process (unwrap! (map-get? manufacturing-processes { process-id: process-id }) ERR-NOT-FOUND))
      (batch-id (var-get next-batch-id))
    )
    (asserts! (is-authorized-operator) ERR-NOT-AUTHORIZED)
    (asserts! (>= input-resources (get resource-requirements process)) ERR-INSUFFICIENT-RESOURCES)

    (map-set production-batches
      { batch-id: batch-id }
      {
        process-id: process-id,
        operator: tx-sender,
        start-time: block-height,
        end-time: u0,
        input-resources: input-resources,
        actual-output: u0,
        quality-score: u0,
        efficiency-achieved: u0,
        status: "in-progress"
      }
    )

    (var-set next-batch-id (+ batch-id u1))
    (ok batch-id)
  )
)

;; Complete a production batch
(define-public (complete-production-batch (batch-id uint) (actual-output uint) (quality-score uint))
  (let
    (
      (batch (unwrap! (map-get? production-batches { batch-id: batch-id }) ERR-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get operator batch)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status batch) "in-progress") ERR-INVALID-INPUT)
    (asserts! (<= quality-score u100) ERR-INVALID-INPUT)

    (let
      (
        (efficiency (/ (* actual-output u100) (get input-resources batch)))
      )
      (map-set production-batches
        { batch-id: batch-id }
        (merge batch {
          end-time: block-height,
          actual-output: actual-output,
          quality-score: quality-score,
          efficiency-achieved: efficiency,
          status: "completed"
        })
      )

      ;; Update process efficiency rating based on this batch
      (try! (update-process-efficiency (get process-id batch) efficiency))

      (ok true)
    )
  )
)

;; Optimize process parameters
(define-public (optimize-process (process-id uint) (temp-min uint) (temp-max uint) (ph-min uint) (ph-max uint) (nutrient-conc uint) (oxygen-level uint))
  (let
    (
      (process (unwrap! (map-get? manufacturing-processes { process-id: process-id }) ERR-NOT-FOUND))
    )
    (asserts! (or (is-eq tx-sender (get creator process)) (is-authorized-operator)) ERR-NOT-AUTHORIZED)
    (asserts! (< temp-min temp-max) ERR-INVALID-INPUT)
    (asserts! (< ph-min ph-max) ERR-INVALID-INPUT)
    (asserts! (var-get optimization-enabled) ERR-NOT-AUTHORIZED)

    (map-set optimization-parameters
      { process-id: process-id }
      {
        temperature-range: { min: temp-min, max: temp-max },
        ph-range: { min: ph-min, max: ph-max },
        nutrient-concentration: nutrient-conc,
        oxygen-level: oxygen-level,
        last-optimized: block-height
      }
    )

    (ok true)
  )
)

;; Allocate resources to a process
(define-public (allocate-resources (process-id uint) (resource-type (string-ascii 32)) (amount uint) (duration uint))
  (let
    (
      (process (unwrap! (map-get? manufacturing-processes { process-id: process-id }) ERR-NOT-FOUND))
    )
    (asserts! (is-authorized-operator) ERR-NOT-AUTHORIZED)
    (asserts! (> amount u0) ERR-INVALID-INPUT)
    (asserts! (> duration u0) ERR-INVALID-INPUT)

    (map-set resource-allocations
      { process-id: process-id, resource-type: resource-type }
      {
        allocated-amount: amount,
        reserved-until: (+ block-height duration),
        allocator: tx-sender
      }
    )

    (ok true)
  )
)

;; Authorize an operator
(define-public (authorize-operator (operator principal))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (map-set authorized-operators { operator: operator } { authorized: true })
    (ok true)
  )
)

;; Private Functions

;; Update process efficiency rating
(define-private (update-process-efficiency (process-id uint) (new-efficiency uint))
  (let
    (
      (process (unwrap! (map-get? manufacturing-processes { process-id: process-id }) ERR-NOT-FOUND))
      (current-efficiency (get efficiency-rating process))
      (updated-efficiency (/ (+ current-efficiency new-efficiency) u2))
    )
    (map-set manufacturing-processes
      { process-id: process-id }
      (merge process { efficiency-rating: updated-efficiency })
    )
    (ok true)
  )
)

;; Read-only Functions

;; Get process details
(define-read-only (get-process (process-id uint))
  (map-get? manufacturing-processes { process-id: process-id })
)

;; Get batch details
(define-read-only (get-batch (batch-id uint))
  (map-get? production-batches { batch-id: batch-id })
)

;; Get optimization parameters
(define-read-only (get-optimization-parameters (process-id uint))
  (map-get? optimization-parameters { process-id: process-id })
)

;; Get resource allocation
(define-read-only (get-resource-allocation (process-id uint) (resource-type (string-ascii 32)))
  (map-get? resource-allocations { process-id: process-id, resource-type: resource-type })
)

;; Get next process ID
(define-read-only (get-next-process-id)
  (var-get next-process-id)
)

;; Get next batch ID
(define-read-only (get-next-batch-id)
  (var-get next-batch-id)
)
