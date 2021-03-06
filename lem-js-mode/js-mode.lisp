(defpackage :lem-js-mode
  (:use :cl :lem :lem.language-mode)
  (:export :js-mode
           :*js-mode-hook*))
(in-package :lem-js-mode)

(defvar *js-mode-hook* '())


#| 
link : 
  https://developer.mozilla.org/ja/docs/Web/JavaScript/Guide/Grammar_and_types 
  https://developer.mozilla.org/ja/docs/Web/JavaScript/Reference/Lexical_grammar

|#
(defvar *js-floating-point-literals* "\\b([+-]?[1-9]\\d*(.\\d)?([Ee][+-]?\\d+)?)\\b")
(defvar *js-integer-literals* "\\b([1-9]\\d*|0+|0[bB][01]+|0[oO][0-7]+|0[xX][\\da-fA-F]+)\\b")
(defvar *js-boolean-literals* "(true|false)")
(defvar *js-null-literals* "(null)")
(defvar *js-nan-literals* "(NaN)")
(defvar *js-undefined-literals* "(undefined)")

(defvar *js-key-words* '("break" "case" "catch" "class" "const" "continue" "debugger" "default"
                         "delete" "do" "else" "export" "extends" "finally" "for" 
                         "function"  "if" "import" "in" "instanceof" 
                         "let" "new" "return" "super"
                         "switch" "this" "throw" "try" "typeof" "var" "void" "while"
                         "with" "yield")) ;; TODO function* yeild*
(defvar *js-future-key-words* '("enum" "implements" "static" "public" 
                                "package" "interface" "protected" "private" "await"))

(defvar *js-white-space* (list (code-char #x9) (code-char #xb) (code-char #xc) 
                               (code-char #x20) (code-char #xa0))) ;;TODO 
(defvar *js-line-terminators* (list (code-char #x0a) (code-char #x0d)
                                    (code-char #x2028) (code-char #x2029)))

(defvar *js-callable-paren* "(\\(|\\))")
(defvar *js-block-paren* "({|})")
(defvar *js-array-paren* "([|])")

(defvar *js-arithmetic-operators* '("+" "-" "*" "/" "%" "**" "++" "--"))
(defvar *js-assignment-operators* '("=" "+=" "-=" "*=" "/=" "%=" "**=" "<<=" ">>=" ">>>=" 
                                    "&=" "\\^=" "\\|="))
(defvar *js-bitwise-operators* '("&" "|" "^" "~" "<<" ">>" ">>>"))
(defvar *js-comma-operators* '(","))
(defvar *js-comparison-operators* '("==" "!=" "===" "!==" ">" ">=" "<" "<="))
(defvar *js-logical-operators* '("&&" "||" "!"))
(defvar *js-other-symbols* '(":" "?" "=>"))

(defvar *js-spaces* (append *js-white-space* *js-line-terminators*))

(defvar *js-builtin-operators* (append *js-arithmetic-operators* 
                               *js-assignment-operators* 
                               *js-bitwise-operators* 
                               *js-comma-operators* 
                               *js-comparison-operators* 
                               *js-logical-operators* 
                               *js-other-symbols*))

(defun tokens (boundary strings)
  (let ((alternation
         `(:alternation ,@(sort (copy-list strings) #'> :key #'length))))
    (if boundary
        `(:sequence ,boundary ,alternation ,boundary)
        alternation)))

(defun make-tm-string-region (sepalator)
  (make-tm-region `(:sequence ,sepalator)
                  `(:sequence ,sepalator)
                  :name 'syntax-string-attribute
                  :patterns (make-tm-patterns (make-tm-match "\\\\."))))

(defun make-tmlanguage-js ()
  (let* ((patterns (make-tm-patterns
                    (make-tm-region "//" "$" :name 'syntax-comment-attribute)
                    (make-tm-region "/\\*" "\\*/" :name 'syntax-comment-attribute)
                    (make-tm-match (tokens :word-boundary *js-key-words*)
                                   :name 'syntax-keyword-attribute)
                    (make-tm-match (tokens :word-boundary *js-future-key-words*)
                                   :name 'syntax-keyword-attribute)
                    (make-tm-match (tokens nil  *js-builtin-operators*)
                                   :name 'syntax-builtin-attribute)
                    (make-tm-string-region "\"")
                    (make-tm-string-region "'")
                    (make-tm-string-region "`")
                    (make-tm-match *js-undefined-literals*
                                   :name 'syntax-constant-attribute)
                    (make-tm-match *js-boolean-literals*
                                   :name 'syntax-constant-attribute)
                    (make-tm-match *js-null-literals*
                                   :name 'syntax-constant-attribute)
                    (make-tm-match *js-nan-literals*
                                   :name 'syntax-constant-attribute)
                    (make-tm-match *js-integer-literals*
                                   :name 'syntax-constant-attribute)
                    (make-tm-match *js-floating-point-literals*
                                   :name 'syntax-constant-attribute))))
    (make-tmlanguage :patterns patterns)))

(defvar *js-syntax-table*
  (let ((table (make-syntax-table
                :space-chars *js-spaces*
                :paren-pairs '((#\( . #\))
                               (#\{ . #\})
                               (#\[ . #\]))
                :string-quote-chars '(#\" #\')
                :block-string-pairs '(("`" . "`"))
                :line-comment-string "//"))
        (tmlanguage (make-tmlanguage-js)))
    (set-syntax-parser table tmlanguage)
    table))

(define-major-mode js-mode language-mode
    (:name "js"
     :keymap *js-mode-keymap*
     :syntax-table *js-syntax-table*)
  (setf (variable-value 'enable-syntax-highlight) t
        (variable-value 'indent-tabs-mode) nil
        (variable-value 'tab-width) 2
        (variable-value 'calc-indent-function) 'js-calc-indent
        (variable-value 'line-comment) "//"
        (variable-value 'beginning-of-defun-function) 'beginning-of-defun
        (variable-value 'end-of-defun-function) 'end-of-defun)
  (run-hooks *js-mode-hook*))

#| 
link : 

|#
(defun js-calc-indent (point)
  (with-point ((point point))
    (let ((tab-width (variable-value 'tab-width :default point))
          (column (point-column point)))
      (+ column (- tab-width (rem column tab-width))))))

(defun beginning-of-defun (point n)
  (loop :repeat n :do (search-backward-regexp point "^\\w")))

(defun end-of-defun (point n)
  (with-point ((p point))
    (loop :repeat n
          :do (line-offset p 1)
              (unless (search-forward-regexp p "^\\w") (return)))
    (line-start p)
    (move-point point p)))

(pushnew (cons "\\.js$" 'js-mode) *auto-mode-alist* :test #'equal)
