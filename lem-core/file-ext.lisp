(in-package :lem)

(export '(*auto-mode-alist*))

(defvar *auto-mode-alist* nil)

(defun scan-var/val (str start)
  (multiple-value-bind (start end reg-starts reg-ends)
      (ppcre:scan "\\s*([a-zA-Z0-9-_]+)\\s*:\\s*" str :start start)
    (when start
      (let ((var (subseq str
                         (aref reg-starts 0)
                         (aref reg-ends 0))))
        (multiple-value-bind (val end)
            (handler-bind ((error (lambda (c)
                                    (declare (ignore c))
                                    (return-from scan-var/val))))
              (let ((*read-eval* nil))
                (read-from-string str nil nil :start end)))
          (values end var val))))))

(defun set-file-property (buffer var val)
  (cond ((string-equal var "mode")
         (let ((mode (find-mode-from-name val)))
           (when mode
             (change-buffer-mode buffer mode))))
        (t
         (let ((ev (find-editor-variable var)))
           (if ev
               (setf (variable-value ev :buffer buffer) val)
               (setf (buffer-value buffer (string-downcase var)) val))))))

(defun scan-line-property-list (buffer str)
  (loop :with i := 0
        :do (multiple-value-bind (pos var val)
                (scan-var/val str i)
              (unless pos (return))
              (set-file-property buffer var val)
              (setf i pos))))

(defun scan-file-property-list (buffer)
  (with-point ((cur-point (buffer-point buffer)))
    (buffer-start cur-point)
    (when (ppcre:scan "^#!" (line-string cur-point))
      (line-offset cur-point 1))
    (loop :until (end-line-p cur-point)
          :for string := (line-string cur-point)
          :do (ppcre:register-groups-bind (result)
                  ("-\\*-(.*)-\\*-" string)
                (when result
                  (scan-line-property-list buffer result)
                  (return)))
              (if (string= "" (string-trim '(#\space #\tab) string))
                  (line-offset cur-point 1)
                  (return)))))

(defun prepare-auto-mode (buffer)
  (let* ((filename (file-namestring (buffer-filename buffer)))
         (elt (find-if (lambda (elt)
                         (ppcre:scan (car elt) filename))
                       *auto-mode-alist*)))
    (when elt
      (change-buffer-mode buffer (cdr elt)))))

(defun detect-external-format-from-file (pathname)
  (values (let ((encoding (inq:detect-encoding (pathname pathname) :jp)))
            #+lispworks
            (if (eq encoding :cp932)
                :shift-jis
                encoding)
            #-lispworks
            encoding)
          (or (inq:detect-end-of-line (pathname pathname)) :lf)))

(setf *external-format-function* 'detect-external-format-from-file)
