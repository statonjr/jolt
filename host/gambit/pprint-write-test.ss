;; Run after chez --script host/gambit/gen-boot.ss full.
(##include "boot-full.ss")

(define failures 0)
(define checks 0)
(define (check label source expected)
  (set! checks (+ checks 1))
  (let ((actual (guard (e (#t (display-exception e) "THREW"))
                  (jolt-pr-readable (jolt-compile-eval source "user")))))
    (if (equal? actual expected)
        (printf "  ok     ~a\n" label)
        (begin
          (set! failures (+ failures 1))
          (printf "  FAIL   ~a: got ~a expected ~a\n" label actual expected)))))

(check "PrettyWriter is bound"
       "(bound? #'clojure.pprint/PrettyWriter)" "true")
(check "custom dispatcher uses core print"
       "(clojure.pprint/write {:n 7} :stream nil :dispatch (fn [x] (print (str \"W-\" (:n x)))))"
       "\"W-7\"")
(check "rebound writer receives output"
       "(let [writes (atom []) w (reify java.io.Writer (write [this s] (swap! writes conj s)))] (binding [*out* w] (print \"routed\")) @writes)"
       "[\"routed\"]")
(printf "pprint-write-test: ~a checks, ~a failure(s)\n" checks failures)
(exit (if (= failures 0) 0 1))
