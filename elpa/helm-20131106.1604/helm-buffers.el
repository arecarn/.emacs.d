;;; helm-buffers.el --- helm support for buffers.

;; Copyright (C) 2012 ~ 2013 Thierry Volpiatto <thierry.volpiatto@gmail.com>

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Code:

(require 'cl)
(require 'helm)
(require 'helm-utils)
(require 'helm-elscreen)
(require 'helm-grep)
(require 'helm-regexp)

(declare-function ido-make-buffer-list "ido" (default))

(defgroup helm-buffers nil
  "Buffers related Applications and libraries for Helm."
  :group 'helm)

(defcustom helm-boring-buffer-regexp-list
  '("\\` " "\\*helm" "\\*helm-mode" "\\*Echo Area" "\\*Minibuf")
  "The regexp list that match boring buffers.
Buffer candidates matching these regular expression will be
filtered from the list of candidates if the
`helm-skip-boring-buffers' candidate transformer is used."
  :type  '(repeat (choice regexp))
  :group 'helm-buffers)

(defcustom helm-buffers-favorite-modes '(lisp-interaction-mode
                                         emacs-lisp-mode
                                         text-mode
                                         org-mode)
  "List of preferred mode to open new buffers with."
  :type '(repeat (choice function))
  :group 'helm-buffers)

(defcustom helm-buffer-max-length 20
  "Max length of buffer names before truncate.
When disabled (nil) use the longest buffer-name length found."
  :group 'helm-buffers
  :type  '(choice (const :tag "Disabled" nil)
           (integer :tag "Length before truncate")))

(defcustom helm-buffer-details-flag t
  "Always show details in buffer list when non--nil."
  :group 'helm-buffers
  :type 'boolean)


;;; Faces
;;
;;
(defface helm-buffer-saved-out
    '((t (:foreground "red" :background "black")))
  "Face used for buffer files modified outside of emacs."
  :group 'helm-buffers)

(defface helm-buffer-not-saved
    '((t (:foreground "Indianred2")))
  "Face used for buffer files not already saved on disk."
  :group 'helm-buffers)

(defface helm-buffer-size
    '((((background dark)) :foreground "RosyBrown")
      (((background light)) :foreground "SlateGray"))
  "Face used for buffer size."
  :group 'helm-buffers)

(defface helm-buffer-process
    '((t (:foreground "Sienna3")))
  "Face used for process status in buffer."
  :group 'helm-buffers)


;;; Buffers keymap
;;
(defvar helm-buffer-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map helm-map)
    (define-key map (kbd "C-c ?")     'helm-buffer-help)
    ;; No need to have separate command for grep and zgrep
    ;; as we don't use recursivity for buffers.
    ;; So use zgrep for both as it is capable to handle non--compressed files.
    (define-key map (kbd "M-g s")     'helm-buffer-run-zgrep)
    (define-key map (kbd "C-s")       'helm-buffers-run-multi-occur)
    (define-key map (kbd "C-c o")     'helm-buffer-switch-other-window)
    (define-key map (kbd "C-c C-o")   'helm-buffer-switch-other-frame)
    (define-key map (kbd "C-c =")     'helm-buffer-run-ediff)
    (define-key map (kbd "M-=")       'helm-buffer-run-ediff-merge)
    (define-key map (kbd "C-=")       'helm-buffer-diff-persistent)
    (define-key map (kbd "M-U")       'helm-buffer-revert-persistent)
    (define-key map (kbd "M-D")       'helm-buffer-run-kill-buffers)
    (define-key map (kbd "C-x C-s")   'helm-buffer-save-persistent)
    (define-key map (kbd "C-M-%")     'helm-buffer-run-query-replace-regexp)
    (define-key map (kbd "M-%")       'helm-buffer-run-query-replace)
    (define-key map (kbd "M-m")       'helm-toggle-all-marks)
    (define-key map (kbd "M-a")       'helm-mark-all)
    (define-key map (kbd "C-]")       'helm-toggle-buffers-details)
    (define-key map (kbd "C-c a")     'helm-buffers-toggle-show-hidden-buffers)
    map)
  "Keymap for buffer sources in helm.")

(defvar helm-buffers-ido-virtual-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map helm-map)
    (define-key map (kbd "C-c ?")   'helm-buffers-ido-virtual-help)
    (define-key map (kbd "C-c o")   'helm-ff-run-switch-other-window)
    (define-key map (kbd "C-c C-o") 'helm-ff-run-switch-other-frame)
    (define-key map (kbd "M-g s")   'helm-ff-run-grep)
    (define-key map (kbd "M-g z")   'helm-ff-run-zgrep)
    (define-key map (kbd "M-D")     'helm-ff-run-delete-file)
    (define-key map (kbd "C-c C-x") 'helm-ff-run-open-file-externally)
    map))


(defvar helm-buffers-list-cache nil)
(defvar helm-buffer-max-len-mode nil)
(defvar helm-source-buffers-list
  `((name . "Buffers")
    (init . (lambda ()
              ;; Issue #51 Create the list before `helm-buffer' creation.
              (setq helm-buffers-list-cache (helm-buffer-list))
              (let ((result (loop for b in helm-buffers-list-cache
                                  maximize (length b) into len-buf
                                  maximize (length (with-current-buffer b
                                                     (symbol-name major-mode)))
                                  into len-mode
                                  finally return (cons len-buf len-mode))))
                (unless helm-buffer-max-length
                  (setq helm-buffer-max-length (car result)))
                (unless helm-buffer-max-len-mode
                  ;; If a new buffer is longer that this value
                  ;; this value will be updated
                  (setq helm-buffer-max-len-mode (cdr result))))))
    (candidates . helm-buffers-list-cache)
    (type . buffer)
    (match helm-buffer-match-major-mode)
    (persistent-action . helm-buffers-list-persistent-action)
    (keymap . ,helm-buffer-map)
    (volatile)
    (no-delay-on-input)
    (mode-line . helm-buffer-mode-line-string)
    (persistent-help
     . "Show this buffer / C-u \\[helm-execute-persistent-action]: Kill this buffer")))

(defvar helm-source-buffer-not-found
  `((name . "Create buffer")
    (dummy)
    (keymap . ,helm-map)
    (action . (lambda (candidate)
                (let ((mjm (and helm-current-prefix-arg
                                (intern (helm-comp-read
                                         "Major-mode: "
                                         helm-buffers-favorite-modes))))
                      (buffer (get-buffer-create candidate)))
                  (if mjm
                      (with-current-buffer buffer (funcall mjm))
                      (set-buffer-major-mode buffer))
                  (helm-switch-to-buffer buffer))))))

(defvar helm-source-ido-virtual-buffers
  `((name . "Ido virtual buffers")
    (candidates . (lambda ()
                    (let (ido-temp-list
                          ido-ignored-list
                          (ido-process-ignore-lists t))
                      (when ido-use-virtual-buffers
                        (ido-add-virtual-buffers-to-list)
                        ido-virtual-buffers))))
    (keymap . ,helm-buffers-ido-virtual-map)
    (mode-line . helm-buffers-ido-virtual-mode-line-string)
    (action . (("Find file" . helm-find-many-files)
               ("Find file other window" . find-file-other-window)
               ("Find file other frame" . find-file-other-frame)
               ("Find file as root" . helm-find-file-as-root)
               ("Grep File(s) `C-u recurse'" . helm-find-files-grep)
               ("Zgrep File(s) `C-u Recurse'" . helm-ff-zgrep)
               ("View file" . view-file)
               ("Delete file(s)" . helm-delete-marked-files)
               ("Open file externally (C-u to choose)"
                . helm-open-file-externally)))))


(defun helm-buffer-list ()
  "Return the current list of buffers.
Currently visible buffers are put at the end of the list.
See `ido-make-buffer-list' for more infos."
  (require 'ido)
  (let ((ido-process-ignore-lists t)
        ido-ignored-list
        ido-use-virtual-buffers)
    (ido-make-buffer-list nil)))

(defun helm-buffer-size (buffer)
  "Return size of BUFFER."
  (with-current-buffer buffer
    (save-restriction
      (widen)
      (helm-file-human-size
       (- (position-bytes (point-max))
          (position-bytes (point-min)))))))

(defun helm-buffer-details (buffer &optional details)
  (let* ((mode (with-current-buffer buffer (symbol-name major-mode)))
         (buf (get-buffer buffer))
         (size (propertize (helm-buffer-size buf)
                           'face 'helm-buffer-size))
         (proc (get-buffer-process buf))
         (dir (with-current-buffer buffer (abbreviate-file-name default-directory)))
         (file-name (helm-aif (buffer-file-name buf) (abbreviate-file-name it)))
         (name (buffer-name buf))
         (name-prefix (when (file-remote-p dir)
                        (propertize "@ " 'face 'helm-ff-prefix))))
    (cond
      ( ;; A dired buffer.
       (rassoc buf dired-buffers)
       (list
        (concat name-prefix
                (propertize name 'face 'helm-ff-directory
                            'help-echo dir))
        size mode
        (and details (propertize (format "(in `%s')" dir) 'face 'helm-buffer-process))))
      ;; A buffer file modified somewhere outside of emacs.=>red
      ((and file-name (file-exists-p file-name)
            (not (verify-visited-file-modtime buf)))
       (list
        (concat name-prefix
                (propertize name 'face 'helm-buffer-saved-out
                            'help-echo file-name))
        size mode
        (and details (propertize (format "(in `%s')" dir) 'face 'helm-buffer-process))))
      ;; A new buffer file not already saved on disk.=>indianred2
      ((and file-name (not (verify-visited-file-modtime buf)))
       (list
        (concat name-prefix
                (propertize name 'face 'helm-buffer-not-saved
                            'help-echo file-name))
        size mode
        (and details (propertize (format "(in `%s')" dir) 'face 'helm-buffer-process))))
      ;; A buffer file modified and not saved on disk.=>orange
      ((and file-name (buffer-modified-p buf))
       (list
        (concat name-prefix
                (propertize name 'face 'helm-ff-symlink
                            'help-echo file-name))
        size mode
        (and details (propertize (format "(in `%s')" dir) 'face 'helm-buffer-process))))
      ;; A buffer file not modified and saved on disk.=>green
      (file-name
       (list
        (concat name-prefix
                (propertize name 'face 'font-lock-type-face
                            'help-echo file-name))
        size mode
        (and details (propertize (format "(in `%s')" dir) 'face 'helm-buffer-process))))
      ;; Any non--file buffer.=>grey italic
      (t (list
          (concat (when proc name-prefix)
                  (propertize name 'face 'italic
                              'help-echo buffer))
          size mode
          (and details
               (propertize
                (if proc
                    (format "(%s %s in `%s')"
                            (process-name proc)
                            (process-status proc) dir)
                    (format "(in `%s')" dir))
                'face 'helm-buffer-process)))))))

(defun helm-highlight-buffers (buffers source)
  "Transformer function to highlight BUFFERS list.
Should be called after others transformers i.e (boring buffers)."
  (loop for i in buffers
        for (name size mode meta) = (if helm-buffer-details-flag
                                        (helm-buffer-details i 'details)
                                        (helm-buffer-details i))
        for truncbuf = (if (> (string-width name) helm-buffer-max-length)
                           (helm-substring-by-width name helm-buffer-max-length)
                           (concat name (make-string
                                         (- (+ helm-buffer-max-length 3)
                                            (string-width name)) ? )))
        for len = (length mode)
        when (> len helm-buffer-max-len-mode) do (setq helm-buffer-max-len-mode len)
        for fmode = (concat (make-string (- (max helm-buffer-max-len-mode len) len) ? )
                            mode)
        ;; The max length of a number should be 1023.9X where X is the
        ;; units, this is 7 characters.
        for formatted-size = (format "%7s" size)
        collect (cons (concat truncbuf "\t" formatted-size "  " fmode "  " meta)
                      i)))

(defun helm-toggle-buffers-details ()
  (interactive)
  (when helm-alive-p
    (setq helm-buffer-details-flag (not helm-buffer-details-flag))
    (helm-force-update (car (split-string (helm-get-selection nil t))))))

(defun helm-buffers-sort-transformer (candidates _source)
  (if (string= helm-pattern "")
      candidates
      (sort candidates
            #'(lambda (s1 s2)
                (< (string-width s1) (string-width s2))))))


(defun helm-buffer-match-major-mode (candidate)
  "Match maybe buffer by major-mode.
If you give a major-mode or partial major-mode,
it will list all buffers of this major-mode and/or buffers with name
matching this major-mode.
If you add a space after major-mode and then a space,
it will match all buffers of the major-mode
before space matching pattern after space.
If you give a pattern which doesn't match a major-mode, it will search buffer
with name matching pattern."
  (let* ((cand (replace-regexp-in-string "^\\s-\\{1\\}" "" candidate))
         (buf  (get-buffer cand))
         (match-mjm (lambda (str mjm)
                      ;; Avoid matching all modes when entering only "mode".
                      (and (not (string= str "mode"))
                           (string-match str mjm)))))
    (when buf
      (with-current-buffer buf
        (let ((mjm   (symbol-name major-mode))
              (split (split-string helm-pattern)))
          (cond ((string-match "^@" helm-pattern)
                 (or (helm-buffers-match-inside cand split)
                     (string-match helm-pattern cand)))
                ((string-match "\\s-$" helm-pattern)
                 (funcall match-mjm (car split) mjm))
                ((string-match "\\s-[@]" helm-pattern)
                 (and (or (funcall match-mjm (car split) mjm)
                          (string-match (car split) cand))
                      (helm-buffers-match-inside cand (cdr split))))
                ((string-match "\\s-" helm-pattern)
                 (and (funcall match-mjm (car split) mjm)
                      (loop for i in (cdr split) always (string-match i cand))))
                (t (or (funcall match-mjm helm-pattern mjm)
                       (string-match helm-pattern cand)))))))))

(defun helm-buffers-match-inside (candidate lst)
  (loop for i in lst
        always
        (cond ((string-match "\\`[\\]@" i)
               (string-match i candidate))
              ((string-match "\\`@\\(.*\\)" i)
               (save-excursion
                 (let ((str (match-string 1 i)))
                   (goto-char (point-min))
                   (re-search-forward str nil t))))
              (t (string-match i candidate)))))


(defun helm-buffer-query-replace-1 (&optional regexp-flag)
  "Query replace in marked buffers.
If REGEXP-FLAG is given use `query-replace-regexp'."
  (let ((fn     (if regexp-flag 'query-replace-regexp 'query-replace))
        (prompt (if regexp-flag "Query replace regexp" "Query replace"))
        (bufs   (helm-marked-candidates)))
    (loop with replace = (query-replace-read-from prompt regexp-flag)
          with tostring = (unless (consp replace)
                            (query-replace-read-to
                             replace prompt regexp-flag))
          for buf in bufs
          do
          (save-window-excursion
            (helm-switch-to-buffer buf)
            (save-excursion
              (let ((case-fold-search t))
                (goto-char (point-min))
                (if (consp replace)
                    (apply fn (list (car replace) (cdr replace)))
                    (apply fn (list replace tostring)))))))))

(defun helm-buffer-query-replace-regexp (candidate)
  (helm-buffer-query-replace-1 'regexp))

(defun helm-buffer-query-replace (candidate)
  (helm-buffer-query-replace-1))

(defun helm-buffer-toggle-diff (candidate)
  "Toggle diff buffer CANDIDATE with it's file."
  (let (helm-persistent-action-use-special-display)
    (helm-aif (get-buffer-window "*Diff*")
        (progn (kill-buffer "*Diff*")
               (set-window-buffer it helm-current-buffer))
      (diff-buffer-with-file (get-buffer candidate)))))

;;;###autoload
(defun helm-buffer-diff-persistent ()
  "Toggle diff buffer without quitting helm."
  (interactive)
  (helm-attrset 'diff-action 'helm-buffer-toggle-diff)
  (helm-execute-persistent-action 'diff-action))

(defun helm-buffer-revert-and-update (candidate)
  (let ((marked (helm-marked-candidates)))
    (loop for buf in marked do (helm-revert-buffer buf))
    (when (> (length marked) 1) (helm-unmark-all))
    (helm-force-update candidate)))

;;;###autoload
(defun helm-buffer-revert-persistent ()
  "Revert buffer without quitting helm."
  (interactive)
  (helm-attrset 'revert-action '(helm-buffer-revert-and-update . never-split))
  (helm-execute-persistent-action 'revert-action))

(defun helm-buffer-save-and-update (candidate)
  (let ((marked (helm-marked-candidates))
        (enable-recursive-minibuffers t))
    (loop for buf in marked do
          (with-current-buffer (get-buffer buf)
            (save-buffer)))
    (when (> (length marked) 1) (helm-unmark-all))
    (helm-force-update candidate)))

;;;###autoload
(defun helm-buffer-save-persistent ()
  "Save buffer without quitting helm."
  (interactive)
  (helm-attrset 'save-action '(helm-buffer-save-and-update . never-split))
  (helm-execute-persistent-action 'save-action))

;;;###autoload
(defun helm-buffer-run-kill-buffers ()
  "Run kill buffer action from `helm-source-buffers-list'."
  (interactive)
  (helm-quit-and-execute-action 'helm-kill-marked-buffers))

;;;###autoload
(defun helm-buffer-run-grep ()
  "Run Grep action from `helm-source-buffers-list'."
  (interactive)
  (helm-quit-and-execute-action 'helm-grep-buffers))

;;;###autoload
(defun helm-buffer-run-zgrep ()
  "Run Grep action from `helm-source-buffers-list'."
  (interactive)
  (helm-quit-and-execute-action 'helm-zgrep-buffers))

;;;###autoload
(defun helm-buffer-run-query-replace-regexp ()
  "Run Query replace regexp action from `helm-source-buffers-list'."
  (interactive)
  (helm-quit-and-execute-action 'helm-buffer-query-replace-regexp))

;;;###autoload
(defun helm-buffer-run-query-replace ()
  "Run Query replace action from `helm-source-buffers-list'."
  (interactive)
  (helm-quit-and-execute-action 'helm-buffer-query-replace))

;;;###autoload
(defun helm-buffer-switch-other-window ()
  "Run switch to other window action from `helm-source-buffers-list'."
  (interactive)
  (helm-quit-and-execute-action 'switch-to-buffer-other-window))

;;;###autoload
(defun helm-buffer-switch-other-frame ()
  "Run switch to other frame action from `helm-source-buffers-list'."
  (interactive)
  (helm-quit-and-execute-action 'switch-to-buffer-other-frame))

;;;###autoload
(defun helm-buffer-switch-to-elscreen ()
  "Run switch to elscreen  action from `helm-source-buffers-list'."
  (interactive)
  (helm-quit-and-execute-action 'helm-find-buffer-on-elscreen))

;;;###autoload
(defun helm-buffer-run-ediff ()
  "Run ediff action from `helm-source-buffers-list'."
  (interactive)
  (helm-quit-and-execute-action 'helm-ediff-marked-buffers))

(defun helm-buffer-run-ediff-merge ()
  "Run ediff action from `helm-source-buffers-list'."
  (interactive)
  (helm-quit-and-execute-action 'helm-ediff-marked-buffers-merge))

(defun helm-buffers-persistent-kill (buffer)
  "Persistent action to kill buffer."
  (with-current-buffer (get-buffer buffer)
    (if (and (buffer-modified-p)
             (buffer-file-name (current-buffer)))
        (progn
          (save-buffer)
          (kill-buffer buffer))
        (kill-buffer buffer)))
  (helm-delete-current-selection)
  (when (helm-empty-source-p) (helm-next-source))
  (with-helm-temp-hook 'helm-after-persistent-action-hook
    (helm-force-update)))

(defun helm-buffers-list-persistent-action (candidate)
  (if current-prefix-arg
      (helm-buffers-persistent-kill candidate)
      (helm-switch-to-buffer candidate)))

(defun helm-ediff-marked-buffers (candidate &optional merge)
  "Ediff 2 marked buffers or CANDIDATE and `helm-current-buffer'.
With optional arg MERGE call `ediff-merge-buffers'."
  (let ((lg-lst (length (helm-marked-candidates)))
        buf1 buf2)
    (case lg-lst
      (0
       (error "Error:You have to mark at least 1 buffer"))
      (1
       (setq buf1 helm-current-buffer
             buf2 (first (helm-marked-candidates))))
      (2
       (setq buf1 (first (helm-marked-candidates))
             buf2 (second (helm-marked-candidates))))
      (t
       (error "Error:To much buffers marked!")))
    (if merge
        (ediff-merge-buffers buf1 buf2)
        (ediff-buffers buf1 buf2))))

(defun helm-ediff-marked-buffers-merge (candidate)
  "Ediff merge `helm-current-buffer' with CANDIDATE.
See `helm-ediff-marked-buffers'."
  (helm-ediff-marked-buffers candidate t))

(defun helm-multi-occur-as-action (_candidate)
  "Multi occur action for `helm-source-buffers-list'.
Can be used by any source that list buffers."
  (let ((helm-moccur-always-search-in-current
         (if helm-current-prefix-arg
             (not helm-moccur-always-search-in-current)
             helm-moccur-always-search-in-current))
        (buffers (helm-marked-candidates))
        (input (loop for i in (split-string helm-pattern " " t)
                     thereis (and (string-match "\\`@\\(.*\\)" i)
                                  (match-string 1 i)))))
    (helm-multi-occur-1 buffers input)))

;;;###autoload
(defun helm-buffers-run-multi-occur ()
  "Run `helm-multi-occur-as-action' by key."
  (interactive)
  (helm-quit-and-execute-action 'helm-multi-occur-as-action))

(defun helm-buffers-toggle-show-hidden-buffers ()
  (interactive)
  (let ((filter-attrs (helm-attr 'filtered-candidate-transformer
                                 helm-source-buffers-list)))
    (if (memq 'helm-shadow-boring-buffers filter-attrs)
        (helm-attrset 'filtered-candidate-transformer
                      (cons 'helm-skip-boring-buffers
                            (remove 'helm-shadow-boring-buffers
                                    filter-attrs))
                      helm-source-buffers-list t)
        (helm-attrset 'filtered-candidate-transformer
                      (cons 'helm-shadow-boring-buffers
                            (remove 'helm-skip-boring-buffers
                                    filter-attrs))
                      helm-source-buffers-list t))
    (helm-force-update)))


;;; Candidate Transformers
;;
;;
(defun helm-skip-boring-buffers (buffers source)
  (helm-skip-entries buffers helm-boring-buffer-regexp-list))

(defun helm-shadow-boring-buffers (buffers source)
  "Buffers matching `helm-boring-buffer-regexp' will be
displayed with the `file-name-shadow' face if available."
  (helm-shadow-entries buffers helm-boring-buffer-regexp-list))

(defun helm-revert-buffer (candidate)
  (with-current-buffer candidate
    (revert-buffer t t)))

(defun helm-revert-marked-buffers (ignore)
  (mapc 'helm-revert-buffer (helm-marked-candidates)))

(defun helm-kill-marked-buffers (ignore)
  (mapc 'kill-buffer (helm-marked-candidates)))


(define-helm-type-attribute 'buffer
    `((action
       ("Switch to buffer" . helm-switch-to-buffer)
       ,(and (locate-library "popwin") '("Switch to buffer in popup window" . popwin:popup-buffer))
       ("Switch to buffer other window" . switch-to-buffer-other-window)
       ("Switch to buffer other frame" . switch-to-buffer-other-frame)
       ,(and (locate-library "elscreen") '("Display buffer in Elscreen" . helm-find-buffer-on-elscreen))
       ("Query replace regexp" . helm-buffer-query-replace-regexp)
       ("Query replace" . helm-buffer-query-replace)
       ("View buffer" . view-buffer)
       ("Display buffer"   . display-buffer)
       ("Grep buffers (C-u grep all buffers)" . helm-zgrep-buffers)
       ("Multi occur buffer(s)" . helm-multi-occur-as-action)
       ("Revert buffer(s)" . helm-revert-marked-buffers)
       ("Insert buffer" . insert-buffer)
       ("Kill buffer(s)" . helm-kill-marked-buffers)
       ("Diff with file" . diff-buffer-with-file)
       ("Ediff Marked buffers" . helm-ediff-marked-buffers)
       ("Ediff Merge marked buffers" . (lambda (candidate)
                                         (helm-ediff-marked-buffers candidate t))))
      (persistent-help . "Show this buffer")
      (filtered-candidate-transformer helm-skip-boring-buffers
                                      helm-buffers-sort-transformer
                                      helm-highlight-buffers))
  "Buffer or buffer name.")

;;;###autoload
(defun helm-buffers-list ()
  "Preconfigured `helm' to list buffers."
  (interactive)
  (helm :sources '(helm-source-buffers-list
                   helm-source-ido-virtual-buffers
                   helm-source-buffer-not-found)
        :buffer "*helm buffers*"
        :keymap helm-buffer-map
        :truncate-lines t))

(provide 'helm-buffers)

;; Local Variables:
;; byte-compile-warnings: (not cl-functions obsolete)
;; coding: utf-8
;; indent-tabs-mode: nil
;; End:

;;; helm-buffers.el ends here
