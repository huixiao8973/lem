(defpackage :lem-vi-mode.visual
  (:use :cl
        :lem
        :lem-vi-mode.core)
  (:export :vi-visual-char
           :vi-visual-line
           :vi-visual-block))
(in-package :lem-vi-mode.visual)

(defvar *set-visual-function* nil)
(defvar *start-point* nil)
(defvar *visual-overlays* '())

(defvar *visual-keymap* (make-keymap :name '*visual-keymap* :parent *command-keymap*))

(define-key *visual-keymap* "escape" 'vi-visual-end)

(define-vi-state visual (:keymap *visual-keymap*
                         :post-command-hook 'post-command-hook)
  (:disable ()
   (clear-visual-overlays))
  (:enable (function)
   (setf *set-visual-function* function)
   (setf *start-point* (copy-point (current-point) :temporary))))

(defun disable ()
  (clear-visual-overlays))

(defun clear-visual-overlays ()
  (mapc 'delete-overlay *visual-overlays*)
  (setf *visual-overlays* '()))

(defun post-command-hook ()
  (clear-visual-overlays)
  (if (not (eq (current-buffer) (point-buffer *start-point*)))
      (vi-visual-end)
      (funcall *set-visual-function*)))

(defun visual-char ()
  (push (make-overlay *start-point* (current-point) 'region)
        *visual-overlays*))

(defun visual-line ()
  (with-point ((start *start-point*)
               (end (current-point)))
    (when (point< end start) (rotatef start end))
    (line-start start)
    (line-end end)
    (push (make-overlay start end 'region)
          *visual-overlays*)))

(defun visual-block ()
  (with-point ((start *start-point*)
               (end (current-point)))
    (when (point< end start) (rotatef start end))
    (let ((start-column (point-column start))
          (end-column (point-column end)))
      (unless (< start-column end-column)
        (rotatef start-column end-column))
      (apply-region-lines start end
                          (lambda (p)
                            (with-point ((s p) (e p))
                              (move-to-column s start-column)
                              (move-to-column e end-column)
                              (push (make-overlay s e 'region) *visual-overlays*)))))))

(define-command vi-visual-end () ()
  (clear-visual-overlays)
  (change-state 'command))

(define-command vi-visual-char () ()
  (change-state 'visual 'visual-char)
  (message "-- VISUAL --"))

(define-command vi-visual-line () ()
  (change-state 'visual 'visual-line)
  (message "-- VISUAL LINE --"))

(define-command vi-visual-block () ()
  (change-state 'visual 'visual-block)
  (message "-- VISUAL BLOCK --"))
