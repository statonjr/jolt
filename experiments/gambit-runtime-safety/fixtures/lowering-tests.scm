(##include "forms.scm")
(define passed 0)
(define failed 0)
(define (check label expected thunk)
  (let ((actual
         (with-exception-catcher
          (lambda (e)
            (if (expression-parsing-exception? e)
                (list 'parsing (expression-parsing-exception-kind e)
                      (expression-parsing-exception-parameters e))
                (begin (display-exception e) 'unexpected-condition)))
          thunk)))
    (if (equal? actual expected)
        (begin (set! passed (+ passed 1)) (write (list 'PASS label actual)))
        (begin (set! failed (+ failed 1))
               (write (list 'FAIL label 'expected expected 'actual actual))))
    (newline)))
(for-each
 (lambda (n)
   (check (list 'named-let n)
          (if (= n 64) 64
              '(parsing ill-formed-call ("Public lowering argument limit is 64")))
          (lambda ()
            (eval (list 'let 'loop
                        (map (lambda (name) (list name 1)) (names n "p")) n)
                  (interaction-environment))))
   (check (list 'recovery n) 42
          (lambda () (eval '(+ 20 22) (interaction-environment)))))
 '(64 65))
(write (list 'SUMMARY 'passed passed 'failed failed))
(newline)
(exit (if (= failed 0) 0 1))
