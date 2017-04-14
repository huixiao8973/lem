(in-package :cl-user)
(defpackage :lem.lisp-mode
  (:use :cl :lem :lem.listener-mode :lem.language-mode)
  (:export
   :*lisp-mode-keymap*
   :lisp-mode
   :lisp-newline-and-indent
   :lisp-indent-sexp
   :lisp-beginning-of-defun
   :lisp-end-of-defun
   :lisp-current-package
   :lisp-set-package
   :lisp-eval-string
   :lisp-eval-region
   :lisp-eval-defun
   :lisp-eval-last-sexp
   :lisp-load-file
   :lisp-macroexpand
   :lisp-macroexpand-all
   :lisp-describe-symbol
   :lisp-disassemble-symbol
   :lisp-find-definitions
   :complete-symbol
   :lisp-complete-symbol
   :lisp-get-arglist
   :lisp-echo-arglist
   :lisp-self-insert-then-arg-list
   :lisp-comment-or-uncomment-region
   :lisp-comment-region
   :lisp-uncomment-region
   :lisp-eval-print-last-sexp
   :*lisp-repl-mode-keymap*
   :lisp-repl-mode
   :start-lisp-repl
   :lisp-repl-get-prompt
   :lisp-repl-paren-correspond-p
   :lisp-repl-confirm
   :lisp-repl-set-package))
(in-package :lem.lisp-mode)

(define-major-mode lisp-mode language-mode
    (:name "lisp"
     :keymap *lisp-mode-keymap*
     :syntax-table lem-lisp-syntax.syntax-table:*syntax-table*)
  (setf (variable-value 'indent-tabs-mode) nil)
  (setf (variable-value 'enable-syntax-highlight) t)
  (setf (variable-value 'calc-indent-function) 'calc-indent)
  (modeline-add-status-list (lambda (window)
                              (package-name (lisp-current-package
                                             (window-buffer window))))
                            (current-buffer)))

(defun indent-spec (string)
  (let ((arglist (lisp-search-arglist string))
        result)
    (when (and arglist (setf result (position '&body arglist)))
      (return-from indent-spec result))))

(defun calc-indent (point)
  (let ((lem-lisp-syntax.indent:*get-method-function* #'indent-spec))
    (lem-lisp-syntax.indent:calc-indent point)))

(define-key *lisp-mode-keymap* (kbd "C-M-q") 'lisp-indent-sexp)
(define-command lisp-indent-sexp () ()
  (with-point ((end (current-point) :right-inserting))
    (when (form-offset end 1)
      (indent-region (current-point) end))))

(defun beginning-of-defun (point n)
  (with-point ((start point))
    (if (minusp n)
        (dotimes (_ (- n) point)
          (if (start-line-p point)
              (line-offset point -1)
              (line-start point))
          (loop
            (when (char= #\( (character-at point 0))
              (return))
            (unless (line-offset point -1)
              (move-point point start)
              (return-from beginning-of-defun nil))))
        (dotimes (_ n point)
          (loop
            (unless (line-offset point 1)
              (move-point point start)
              (return-from beginning-of-defun nil))
            (when (char= #\( (character-at point 0))
              (return)))))))

(define-key *lisp-mode-keymap* (kbd "C-M-a") 'lisp-beginning-of-defun)
(define-command lisp-beginning-of-defun (n) ("p")
  (beginning-of-defun (current-point) (- n)))

(define-key *lisp-mode-keymap* (kbd "C-M-e") 'lisp-end-of-defun)
(define-command lisp-end-of-defun (n) ("p")
  (if (minusp n)
      (lisp-beginning-of-defun (- n))
      (let ((point (current-point)))
        (dotimes (_ n)
          (with-point ((p point))
            (cond ((and (beginning-of-defun p -1)
                        (point<= p point)
                        (or (form-offset p 1)
                            (progn
                              (move-point point p)
                              (return)))
                        (point< point p))
                   (move-point point p)
                   (skip-whitespace-forward point t)
                   (when (end-line-p point)
                     (character-offset point 1)))
                  (t
                   (form-offset point 1)
                   (skip-whitespace-forward point t)
                   (when (end-line-p point)
                     (character-offset point 1)))))))))

(defun lisp-buffer-package (buffer)
  (let ((package-name (buffer-value buffer "package")))
    (when package-name
      (string-upcase package-name))))

(defun lisp-current-package (&optional (buffer (current-buffer)))
  (or (find-package (lisp-buffer-package buffer))
      (find-package "COMMON-LISP-USER")))

(defun lisp-change-package (package)
  (setf (buffer-value (current-buffer) "package") (package-name package)))

(defun lisp-read-change-package (find-package-function
                                 complete-package-function)
  (let* ((package-name
          (string-upcase
           (prompt-for-line "Package: " ""
                            complete-package-function nil
                            'mh-lisp-package)))
         (package (funcall find-package-function package-name)))
    (cond (package
           (lisp-change-package package) t)
          (t
           (message "Package does not exist: ~a" package-name)
           nil))))

(define-key *lisp-mode-keymap* (kbd "C-c M-p") 'lisp-set-package)
(define-command lisp-set-package () ()
  (lisp-read-change-package
   #'find-package
   #'(lambda (str)
       (completion str
                   (mapcar #'(lambda (pkg)
                               (string-downcase (package-name pkg)))
                           (list-all-packages))))))

(defun scan-current-package (check-package-fn)
  (with-point ((p (current-point)))
    (loop
      (multiple-value-bind (result groups)
          (looking-at (line-start p)
                      "^\\s*\\(in-package (?:#?:|')?([^\)]*)\\)")
        (when result
          (let ((package (funcall check-package-fn (aref groups 0))))
            (when package
              (return package))))
        (unless (line-offset p -1)
          (return))))))

(defun %string-to-exps (str package)
  (let ((str str)
        (exps)
        (eof-value (make-symbol "eof")))
    (do ()
        ((string= "" str))
      (multiple-value-bind (expr i)
          (let ((*package* package))
            (read-from-string str nil eof-value))
        (when (eq expr eof-value)
          (return))
        (push expr exps)
        (setq str (subseq str i))))
    (nreverse exps)))

(defun string-readcase (string &key (start 0) end)
  (ecase (readtable-case *readtable*)
    ((:upcase)
     (string-upcase string :start start :end end))
    ((:downcase)
     (string-downcase string :start start :end end))
    ((:invert :preserve)
     string)))

(defun lisp-eval-in-package (expr package)
  (let* ((string (write-to-string expr))
         (*package* (find-package package)))
    (multiple-value-list (eval (read-from-string string)))))

(defun ldebug-store-value (condition)
  (do ((x)
       (error-p nil))
      (nil)
    (handler-case
        (setq x
              (eval
               (read-from-string
                (prompt-for-string
                 "Type a form to be evaluated: ")
                nil)))
      (error (cdt)
	(setq error-p t)
	(message "~a" cdt)))
    (unless error-p
      (store-value x condition)
      (return))))

(defvar *error-buffer-name* "*error*")

(defun lisp-debugger (condition)
  (let* ((choices (compute-restarts condition))
         (n (length choices)))
    (with-pop-up-typeout-window (out (get-buffer-create *error-buffer-name*) :erase t)
      (format out "~a~%~%" condition)
      (loop
	 for choice in choices
	 for i from 1
	 do (format out "~&[~d] ~a~%" i choice))
      (terpri out)
      (uiop/image:print-backtrace :stream out :count 100))
    (loop
       (redraw-display)
       (handler-case
	   (let* ((str (prompt-for-string "Debug: "))
		  (i (and (stringp str) (parse-integer str :junk-allowed t))))
	     (cond ((and i (<= 1 i n))
		    (let ((restart (nth (1- i) choices)))
		      (cond ((eq 'store-value (restart-name restart))
			     (ldebug-store-value condition))
			    (t
			     (invoke-restart-interactively restart))))
		    (return))
		   (t
		    (let ((x
			   (handler-case (eval (read-from-string str nil))
			     (error (cdt) (format nil "~a" cdt)))))
		      (with-pop-up-typeout-window (out (get-buffer-create "*output*") :erase t)
			(princ x out))))))
	 (editor-abort ()))))
  condition)

(defun %lisp-eval-internal (x point &optional update-point-p)
  (with-point ((cur-point point
			  (if update-point-p
			      :left-inserting
			      :right-inserting)))
    (with-open-stream (io (make-editor-io-stream cur-point t))
      (let* ((error-p)
             (results)
             (*terminal-io* io)
             (*standard-output* io)
             (*standard-input* io)
             (*error-output* io)
             (*query-io* io)
             (*debug-io* io)
             (*trace-output* io)
             (*package* (lisp-current-package)))
        (handler-case-bind (#'lisp-debugger
                            (setq results
                                  (restart-case
                                      (multiple-value-list (eval x))
                                    (editor-abort () :report "Abort.")))
                            (when update-point-p
                              (move-point point cur-point)))
                           ((condition)
                            (setq error-p t)
                            (setq results (list condition))))
        (values results error-p)))))

(defun %lisp-eval (x point
		   &optional update-point-p)
  (multiple-value-bind (results error-p)
      (%lisp-eval-internal x
                           point
                           update-point-p)
    (values results error-p)))

(defun %lisp-eval-string (string point
			  &optional
			    update-point-p (package "COMMON-LISP-USER"))
  (%lisp-eval `(cl:progn ,@(%string-to-exps string package))
              point
              update-point-p))

(define-key *global-keymap* (kbd "M-:") 'lisp-eval-string)
(define-command lisp-eval-string (string)
    ((list (prompt-for-line "Eval: " "" nil nil 'mh-lisp-eval)))
  (let ((output-buffer (get-buffer-create "*output*")))
    (erase-buffer output-buffer)
    (change-buffer-mode output-buffer 'lisp-mode)
    (buffer-unmark output-buffer)
    (message "~{~s~^,~}"
             (%lisp-eval-string string (buffer-start-point output-buffer)
                                nil
                                (lisp-current-package)))
    (when (buffer-modified-p output-buffer)
      (pop-up-typeout-window output-buffer nil))))

(define-key *lisp-mode-keymap* (kbd "C-c C-r") 'lisp-eval-region)
(define-command lisp-eval-region (&optional start end) ("r")
  (unless (or start end)
    (setq start (region-beginning))
    (setq end (region-end)))
  (lisp-eval-string (points-to-string start end))
  t)

(defun lisp-move-and-eval-sexp (move-sexp eval-string-function)
  (let ((str (save-excursion
               (and (funcall move-sexp)
                    (let ((end (form-offset (copy-point (current-point) :temporary) 1)))
                      (when end
                        (points-to-string (current-point) end)))))))
    (when str
      (funcall eval-string-function str)
      t)))

(defun top-of-defun (point)
  (beginning-of-defun (line-end point) -1))

(define-key *lisp-mode-keymap* (kbd "C-M-x") 'lisp-eval-defun)
(define-command lisp-eval-defun () ()
  (lisp-move-and-eval-sexp (lambda () (top-of-defun (current-point)))
                           #'lisp-eval-string))

(define-key *lisp-mode-keymap* (kbd "C-c C-e") 'lisp-eval-last-sexp)
(define-command lisp-eval-last-sexp () ()
  (lisp-move-and-eval-sexp #'backward-sexp #'lisp-eval-string))

(define-key *lisp-mode-keymap* (kbd "C-c l") 'lisp-load-file)
(define-key *lisp-mode-keymap* (kbd "C-c C-l") 'lisp-load-file)
(define-command lisp-load-file (filename) ("fLoad File: ")
  (when (uiop:pathname-equal filename (buffer-directory))
    (setf filename (buffer-filename (current-buffer))))
  (when (and (cl-fad:file-exists-p filename)
             (not (cl-fad:directory-pathname-p filename)))
    (lisp-eval-string
     (format nil "(cl:load ~s)" filename))
    (message "load: ~A" filename)))

(defun lisp-print-error (condition)
  (with-pop-up-typeout-window (out (get-buffer-create *error-buffer-name*) :erase t)
    (format out "~a~%~%" condition)
    (uiop/image:print-backtrace :stream out :count 100)))

(defmacro with-safe-form (&body body)
  `(handler-case
       (handler-bind ((error #'lisp-print-error))
         (values (progn ,@body) nil))
     (error (cdt) (values cdt t))))

(defun %lisp-macroexpand-at-point (macroexpand-symbol)
  (car (lisp-eval-in-package
        `(,macroexpand-symbol
          (let ((*package* (lisp-current-package)))
            (read-from-string
             (points-to-string
              (current-point)
              (form-offset (copy-point (current-point)
				       :temporary)
			   1)))))
        (lisp-current-package))))

(defun %lisp-macroexpand-replace-expr (expr)
  (delete-between-points
   (current-point)
   (form-offset (copy-point (current-point) :temporary) 1))
  (with-open-stream (stream (make-buffer-output-stream (current-point)))
    (pprint expr stream))
  (let ((*package* (lisp-current-package)))
    (read-from-string
     (points-to-string (buffer-start-point (current-buffer))
                       (buffer-end-point (current-buffer))))))

(defun %lisp-macroexpand (macroexpand-symbol buffer-name)
  (multiple-value-bind (expr error-p)
      (with-safe-form
        (let ((expr (%lisp-macroexpand-at-point macroexpand-symbol)))
          (cond ((eq (current-buffer)
                     (get-buffer buffer-name))
                 (%lisp-macroexpand-replace-expr expr))
                (t
                 expr))))
    (unless error-p
      (with-pop-up-typeout-window (out (change-buffer-mode (get-buffer-create buffer-name)
                                                           'lisp-mode)
                                       :focus nil
                                       :erase t)
        (pprint expr out)))))

(define-key *lisp-mode-keymap* (kbd "C-c m") 'lisp-macroexpand)
(define-key *lisp-mode-keymap* (kbd "C-c C-m") 'lisp-macroexpand)
(define-command lisp-macroexpand () ()
  (%lisp-macroexpand 'macroexpand-1 "*macroexpand*"))

(define-key *lisp-mode-keymap* (kbd "C-c M") 'lisp-macroexpand-all)
(define-key *lisp-mode-keymap* (kbd "C-c M-m") 'lisp-macroexpand-all)
(define-command lisp-macroexpand-all () ()
  (%lisp-macroexpand 'swank/backend:macroexpand-all
                     "*macroexpand*"))

(defun lisp-read-symbol (prompt history-name &optional use-default-name)
  (let ((default-name (symbol-string-at-point (current-point))))
    (let ((name (if (and use-default-name default-name)
                    default-name
                    (prompt-for-line prompt
                                     (or default-name "")
                                     'complete-symbol
                                     nil
                                     history-name))))
      (setq name (string-right-trim ":" name))
      (with-safe-form
        (let ((*package* (lisp-current-package)))
          (read-from-string name))))))

(define-key *lisp-mode-keymap* (kbd "C-c C-d") 'lisp-describe-symbol)
(define-command lisp-describe-symbol () ()
  (multiple-value-bind (name error-p)
      (lisp-read-symbol "Describe: " 'mh-describe)
    (unless error-p
      (with-pop-up-typeout-window (out (change-buffer-mode (get-buffer-create "*describe*")
                                                           'lisp-mode)
                                       :erase t)
        (describe name out)))))

(define-key *lisp-mode-keymap* (kbd "C-c M-d") 'lisp-disassemble-symbol)
(define-command lisp-disassemble-symbol () ()
  (multiple-value-bind (name error-p)
      (lisp-read-symbol "Disassemble: " 'mh-disassemble)
    (unless error-p
      (let ((str
             (with-output-to-string (out)
               (handler-case (disassemble name :stream out)
                 (error (condition)
		   (message "~a" condition)
		   (return-from lisp-disassemble-symbol nil))))))
        (with-pop-up-typeout-window (out (change-buffer-mode (get-buffer-create "*disassemble*")
                                                             'lisp-mode))
          (princ str out))))))

(defvar *lisp-find-definition-stack* nil)

(defun find-definitions (name)
  (let ((swank::*buffer-package* (lisp-current-package))
        (swank::*buffer-readtable* *readtable*))
    (swank::find-definitions name)))

(defun lisp-find-definitions-internal (symbol)
  (let ((moves))
    (dolist (definition (find-definitions symbol))
      (destructuring-bind (head &rest alist) definition
        (let ((location (cdr (assoc :location alist))))
          (when location
            (let ((file (second (assoc :file location)))
                  (position (second (assoc :position location))))
              (push (list head file position) moves))))))
    (nreverse moves)))

(defun push-definition-stack (point)
  (push (list (buffer-name (point-buffer point))
              (position-at-point point))
        *lisp-find-definition-stack*))

(define-key *lisp-mode-keymap* (kbd "M-.") 'lisp-find-definitions)
(define-command lisp-find-definitions () ()
  (multiple-value-bind (name error-p)
      (lisp-read-symbol "Find definitions: " 'mh-find-definitions t)
    (unless error-p
      (let ((local-point
             (lem-lisp-syntax.enclosing:search-local-definition
              (current-point) (string-downcase name))))
        (when local-point
          (push-definition-stack (current-point))
          (move-point (current-point) local-point)
          (return-from lisp-find-definitions)))
      (let ((defs))
        (dolist (def (lisp-find-definitions-internal name))
          (destructuring-bind (head file filepos) def
            (declare (ignore head))
            (push (list file
                        (lambda ()
                          (find-file file)
                          (move-to-position (current-point) filepos)
                          (redraw-display)))
                  defs)))
        (push-definition-stack (current-point))
        (cond ((= 1 (length defs))
               (funcall (second (car defs))))
              (t
               (lem.sourcelist:with-sourcelist (sourcelist "*Definitions*")
                 (loop :for (file jump-fun) :in defs
		    :do (lem.sourcelist:append-sourcelist
			 sourcelist
			 (lambda (cur-point)
			   (insert-string cur-point file))
			 jump-fun)))))))))

(define-key *lisp-mode-keymap* (kbd "M-,") 'lisp-pop-find-definition-stack)
(define-command lisp-pop-find-definition-stack () ()
  (let ((elt (pop *lisp-find-definition-stack*)))
    (unless elt
      (return-from lisp-pop-find-definition-stack nil))
    (destructuring-bind (buffer-name offset) elt
      (let ((buffer (get-buffer-create buffer-name)))
        (switch-to-buffer buffer)
        (move-to-position (current-point) offset)))))

(defun %collect-symbols (package package-name external-p)
  (let ((symbols))
    (labels ((f (sym separator)
	       (push (if package
			 (format nil "~a~a~a"
				 package-name
				 separator
				 (string-downcase (string sym)))
			 (string-downcase (string sym)))
		     symbols)))
      (let ((pkg (or package (lisp-current-package))))
        (if external-p
            (do-external-symbols (sym pkg) (f sym ":"))
            (do-symbols (sym pkg) (f sym "::")))))
    (when (null package)
      (flet ((add (name)
	       (push (format nil "~(~a~):" name) symbols)))
        (dolist (p (list-all-packages))
          (add (package-name p))
          (dolist (p (package-nicknames p))
            (add p)))))
    (nreverse (remove-duplicates symbols :test #'string=))))

(defun complete-symbol (string)
  (values nil (mapcar #'first (fuzzy-completions string))))

(defvar *fuzzy-completions* nil)

(defun fuzzy-completions (string &optional (package (lisp-current-package)))
  (unless *fuzzy-completions*
    (swank:swank-require "SWANK-FUZZY")
    (setf *fuzzy-completions* (intern "FUZZY-COMPLETIONS" :swank)))
  (let ((swank::*buffer-package* (lisp-current-package))
        (swank::*buffer-readtable* *readtable*))
    (first (funcall *fuzzy-completions*
                    string
                    (or package (lisp-current-package))))))

(define-key *lisp-mode-keymap* (kbd "C-M-i") 'lisp-complete-symbol)
(define-command lisp-complete-symbol () ()
  (with-point ((start (current-point))
               (end (current-point)))
    (skip-chars-backward start #'syntax-symbol-char-p)
    (skip-chars-forward end #'syntax-symbol-char-p)
    (let ((completions
           (fuzzy-completions (points-to-string start end)
                              (lisp-current-package))))
      (when completions
        (run-completion
         (mapcar (lambda (completion)
                   (lem::make-completion-item :label (first completion)
                                              :detail (fourth completion)
                                              :start start
                                              :end end))
                 completions)
         :auto-insert nil
         :restart-function 'lisp-complete-symbol)))))

(defun analyze-symbol (str)
  (let (package
        external-p)
    (let* ((list (uiop:split-string str :separator ":"))
           (len (length list)))
      (case len
        ((1)
         (setq str (car list)))
        ((2 3)
         (setq package
               (if (equal "" (car list))
                   (find-package :keyword)
                   (find-package
                    (string-readcase (car list)))))
         (unless package
           (return-from analyze-symbol nil))
         (setq str (car (last list)))
         (if (= len 2)
             (setq external-p t)
             (unless (equal "" (cadr list))
               (return-from analyze-symbol nil))))
        (otherwise
         (return-from analyze-symbol nil))))
    (list package str external-p)))

(defun lisp-search-arglist (string)
  (multiple-value-bind (x error-p)
      (ignore-errors
       (destructuring-bind (package symbol-name external-p)
           (analyze-symbol string)
         (declare (ignore external-p))
         (multiple-value-bind (symbol status)
             (find-symbol (string-readcase symbol-name)
                          (or package
                              (lisp-current-package)))
           (if (null status)
               nil
               symbol))))
    (when (and (not error-p)
               (symbolp x)
               (fboundp x))
      (swank/backend:arglist x))))

(defun traverse-form-backward (point look)
  (with-point ((point point))
    (loop
      (loop
        (unless (form-offset point -1) (return))
        (when (start-line-p point) (return-from traverse-form-backward nil)))
      (alexandria:if-let ((result (funcall look point)))
        (return result)
        (unless (scan-lists point -1 1 t)
          (return))))))

(define-key *lisp-mode-keymap* (kbd "C-c C-a") 'lisp-echo-arglist)
(define-command lisp-echo-arglist () ()
  (let ((arglist (traverse-form-backward
                  (current-point)
                  (lambda (point)
                    (let ((name (symbol-string-at-point point)))
                      (when name
                        (swank:operator-arglist name (lisp-current-package))))))))
    (when arglist
      (message "~A" arglist))))

(define-key *lisp-mode-keymap* (kbd "Spc") 'lisp-insert-space-and-echo-arglist)
(define-command lisp-insert-space-and-echo-arglist (n) ("p")
  (insert-character (current-point) #\space n)
  (lisp-echo-arglist))

(define-key *lisp-mode-keymap* (kbd "C-c ;") 'lisp-comment-or-uncomment-region)
(define-command lisp-comment-or-uncomment-region (arg) ("P")
  (if arg
      (lisp-uncomment-region)
      (lisp-comment-region)))

(defun space*-p (point)
  (with-point ((point point))
    (skip-whitespace-forward point t)
    (end-line-p point)))

(define-command lisp-comment-region () ()
  (save-excursion
    (with-point ((start (region-beginning) :right-inserting)
                 (end (region-end) :left-inserting))
      (skip-whitespace-forward start)
      (let ((charpos (point-charpos start)))
        (loop
          (when (same-line-p start end)
            (cond ((space*-p start))
                  (t
                   (insert-string start ";; ")
                   (unless (space*-p end)
                     (insert-character end #\newline))))
            (return))
          (unless (space*-p start)
            (insert-string start ";; "))
          (line-offset start 1 charpos))))))

(define-command lisp-uncomment-region () ()
  (when (buffer-mark-p (current-buffer))
    (with-point ((start (region-beginning) :right-inserting)
                 (end (region-end) :right-inserting))
      (character-offset start -1)
      (loop
        ;; ここを実行中は構文走査がされないのでテキストプロパティが更新されず、ずれていくので後ろから探していく
        (unless (search-comment-start-backward end start)
          (return))
        (when (looking-at end ";")
          (if (looking-at end ";; ")
              (delete-character end 3)
              (loop :while (char= #\; (character-at end 0))
                    :do (delete-character end 1))))))))

(defun check-package (package-name)
  (find-package (string-upcase package-name)))

(defun lisp-idle-timer-function ()
  (when (eq (buffer-major-mode (current-buffer)) 'lisp-mode)
    (let ((package (scan-current-package #'check-package)))
      (when package
        (lisp-change-package package)))))

(defvar *lisp-timer*)
(when (or (not (boundp '*lisp-timer*))
          (not (timer-alive-p *lisp-timer*)))
  (setf *lisp-timer*
        (start-idle-timer "lisp" 110 t 'lisp-idle-timer-function nil
                          (lambda (condition)
                            (pop-up-backtrace condition)
                            (stop-timer *lisp-timer*)))))

(defun lisp-print-values (point values)
  (with-point ((point point :left-inserting))
    (with-open-stream (out (make-buffer-output-stream point))
      (let ((*package* (lisp-current-package)))
        (dolist (v values)
          (pprint v out))))))

(define-key *lisp-mode-keymap* (kbd "C-c C-j") 'lisp-eval-print-last-sexp)
(define-command lisp-eval-print-last-sexp () ()
  (lisp-move-and-eval-sexp
   #'backward-sexp
   #'(lambda (string)
       (unless (start-line-p (current-point)) (insert-character (current-point) #\newline))
       (setq - (first (%string-to-exps string (lisp-current-package))))
       (let ((point (current-point)))
         (let ((values (%lisp-eval - point t)))
           (setq +++ ++ /// //     *** (car ///)
                 ++  +  //  /      **  (car //)
                 +   -  /   values *   (car /))
           (lisp-print-values point values)
           (insert-character point #\newline))))))

(define-major-mode lisp-repl-mode lisp-mode
    (:name "lisp-repl"
	   :keymap *lisp-repl-mode-keymap*
	   :syntax-table lem-lisp-syntax.syntax-table:*syntax-table*)
  (setf (variable-value 'listener-get-prompt-function)
        'lisp-repl-get-prompt)
  (setf (variable-value 'listener-check-confirm-function)
        'lisp-repl-paren-correspond-p)
  (setf (variable-value 'listener-confirm-function)
        'lisp-repl-confirm)
  (listener-mode t))

(define-command start-lisp-repl () ()
  (listener-start "*lisp-repl*" 'lisp-repl-mode))

(defun shorten-package-name (package)
  (car
   (sort (copy-list
          (cons (package-name package)
                (package-nicknames package)))
         #'(lambda (x y)
             (< (length x) (length y))))))

(defun lisp-repl-get-prompt ()
  (format nil "~A> " (shorten-package-name (lisp-current-package))))

(defun lisp-repl-paren-correspond-p (point)
  (loop :with count := 0 :do
     (insert-character point #\))
     (incf count)
     (unless (form-offset (copy-point point :temporary) -1)
       (delete-character point (- count))
       (return (= 1 count)))))

(defun lisp-repl-confirm (point string)
  (setq - (car (%string-to-exps string (lisp-current-package))))
  (multiple-value-bind (values error-p)
      (%lisp-eval - point t)
    (declare (ignore error-p))
    (setq +++ ++ /// //     *** (car ///)
          ++  +  //  /      **  (car //)
          +   -  /   values *   (car /))
    (buffer-end point)
    (lisp-print-values point values)
    (listener-reset-prompt (point-buffer point))))

(define-key *lisp-repl-mode-keymap* (kbd "C-c M-p") 'lisp-repl-set-package)
(define-command lisp-repl-set-package () ()
  (lisp-set-package)
  (listener-reset-prompt)
  t)

(pushnew (cons ".lisp$" 'lisp-mode) *auto-mode-alist* :test #'equal)
(pushnew (cons ".asd$" 'lisp-mode) *auto-mode-alist* :test #'equal)
