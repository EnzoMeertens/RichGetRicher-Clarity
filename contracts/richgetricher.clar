;; Errors.
(define-constant err-invalid-lobby-name (err u101))
(define-constant err-no-lobby (err u102))
(define-constant err-fee-too-high (err u103))
(define-constant err-end-time-invalid (err u104))
(define-constant err-no-games (err u105))
(define-constant err-game-ended (err u106))
(define-constant err-invalid-amount (err u107))
(define-constant err-no-such-game (err u108))

;; Constants.
(define-constant contract-principal (as-contract tx-sender))
(define-constant owner tx-sender)

;; Variables.
(define-data-var lobby-name (string-ascii 32) "Unnamed lobby")
(define-data-var lobby-initialized bool false)
(define-data-var lobby-fee uint u0)
(define-data-var lobby-game-count uint u0)
(define-data-var games-list (list 100 { id: uint, name: (string-ascii 64) }) (list) )

;; Map of participants.
(define-map participants
    { participant: principal, game: uint }
    {
    amount: uint,
    message: (string-ascii 128)
    }
)

;; Map of games.
(define-map games { id: uint }
    {
    id: uint,
    name: (string-ascii 64),
    owner: principal,
    end-time: uint,
    fee: uint,
    ended: bool,
    total-amount: uint,
    leader: principal,
    leader-amount: uint,
    leader-message : (string-ascii 128)
    }
)

;; Get the lobby's games.
(define-read-only (get-lobby)
    (begin
        (asserts! (> (var-get lobby-game-count) u0) err-no-games)
        (ok (var-get games-list))
    )
)

;; Create a new lobby with the given name and fee.
(define-public (create-lobby (name (string-ascii 32)) (fee uint))
    (begin
        (asserts! (>= (len name) u3) err-invalid-lobby-name)
        (asserts! (< fee u1000) err-fee-too-high)

        ;; (print "Initializing lobby...")
        (var-set lobby-name name)
        (var-set lobby-fee fee)
        (var-set lobby-initialized true) ;; Lobby initialized.
        ;; (print "Lobby initialized!")
        (ok (var-get lobby-name))
    )
)

;; Create a new game with the given name, fee and end-time.
(define-public (create-game (name (string-ascii 32)) (fee uint) (end-time uint))
    (begin
        (asserts! (is-eq (var-get lobby-initialized) true) err-no-lobby)
        (asserts! (< fee u1000) err-fee-too-high)
        (asserts! (> end-time u0) err-end-time-invalid)
        ;; (print "Creating new game...")

        (let ((id (+ (var-get lobby-game-count) u1))) ;; Get the lobby's game count plus one.
            (var-set lobby-game-count id) ;; Save the lobby's incremented game count.
            (map-set games { id: id } ;; Create a new game using the lobby's game count as unique ID.
                { 
                id: id,
                owner: tx-sender,
                name: name,
                fee: fee,
                end-time: (+ block-height end-time),
                ended: false,
                leader: owner,
                total-amount: u0,
                leader-amount: u0,
                leader-message: ""
                }
            )
            (var-set games-list (unwrap-panic (as-max-len? (append (var-get games-list) { id: id, name: name }) u100)))
            ;; (print "New game created!")
            (ok id)
        )
    )
)

;; Get game information from the specified game ID.
(define-public (get-game (id uint))
    (begin 
        (asserts! (is-eq (var-get lobby-initialized) true) err-no-lobby)
        (asserts! (> (var-get lobby-game-count) u0) err-no-games)

        (try! (end-game id)) ;; Check (and potentially end) the game.
        (ok (unwrap-panic (map-get? games { id: id }))) ;; Return game state.
    )
)

;; End the given game.
(define-public (end-game (id uint))
    (begin
        (asserts! (is-eq (var-get lobby-initialized) true) err-no-lobby)
        (asserts! (> (var-get lobby-game-count) u0) err-no-games)

        (let ((game (unwrap-panic (map-get? games { id: id })))) ;; Get the game with the given ID.
            (let ((ended (> block-height (get end-time game))))
                (begin
                    (let ((ended-game (merge game 
                        { 
                            ended: ended, ;; Set the game as ended if the end-time block is reached.
                        })))
                        (map-set games { id: id } ended-game) ;; Write the local game back to the global map.
                    )
                )
                (if ended
                    (begin
                        (let ((lobby-owner-share (/ (* (get total-amount game) (var-get lobby-fee)) u1000)))
                            (let ((game-owner-share (/ (* (- (get total-amount game) lobby-owner-share) (get fee game)) u1000)))
                                 (try! (as-contract (stx-transfer? lobby-owner-share contract-principal owner))) ;; Payout to lobby owner.
                                 (try! (as-contract (stx-transfer? game-owner-share contract-principal (get owner game)))) ;; Payout to game owner.
                                 (try! (as-contract (stx-transfer? (- (get total-amount game) lobby-owner-share game-owner-share) contract-principal (get leader game)))) ;; Payout to game leader.
                            )
                        )
                        (ok true)
                    )
                    (ok false)
                )
            )
        )
    )
)

;; Participate in a game with the given amount.
(define-public (participate (id uint) (amount uint) (message (string-ascii 128)))
    (begin
        (asserts! (> amount u0) (err err-invalid-amount))
        (asserts! (is-ok (stx-transfer? amount tx-sender contract-principal)) err-invalid-amount)

        (let ((game (try! (get-game id))))

            (asserts! (is-eq (get ended game) false) err-game-ended)

            (if (not (map-insert participants { participant: tx-sender, game: id } { amount: amount, message: message })) ;; Add the participant with the given amount if the participant does not already exist.
                (let ((existing-participant (map-get? participants { participant: tx-sender, game: id }))) ;; Get the existing participant.
                    (map-set participants { participant: tx-sender, game: id } { amount: (+ (default-to u0 (get amount existing-participant)) amount), message: message }) ;; Increment the amount of the existing participant.
                    ;; (print "Updated participant!")
                )
                ;; (print "New participant!")
            )

            (let ((existing-participant (map-get? participants { participant: tx-sender, game: id }))) ;; Get the existing participant.
                (if (> (default-to u0 (get amount existing-participant)) (get leader-amount game)) ;; Check if the new amount is enough to become the leader.
                    (let ((updated-game (merge game 
                        { 
                            total-amount: (+ (get total-amount game) amount), ;; Increment the game's total amount.
                            leader: tx-sender, ;; Declare the new leader.
                            leader-amount: (default-to u0 (get amount existing-participant)), ;; Set the leader's amount.
                            leader-message: message
                        })))
                        (map-set games { id: id } updated-game) ;; Write the local game back to the global map.
                    )
                    (let ((updated-game (merge game 
                        {
                            total-amount: (+ (get total-amount game) amount) ;; Only increment the game's total amount.
                        })))
                        (map-set games { id: id } updated-game) ;; Write the local game back to the global map.
                    )
                )
            )
        )
        
        (ok true)
    )
)