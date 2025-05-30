;;; org-link-beautify-new.el --- Beautify Org Links -*- lexical-binding: t; -*-

;; Authors: stardiviner <numbchild@gmail.com>
;; Package-Requires: ((emacs "30.1") (org "9.7.17") (nerd-icons "0.0.1") (qrencode "1.3"))
;; Keywords: hypermedia
;; Homepage: https://repo.or.cz/org-link-beautify.git

;; org-link-beautify is free software; you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; org-link-beautify is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
;; or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
;; License for more details.
;;
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Usage:
;;
;; (use-package org-link-beautify
;;   :ensure t
;;   :init (org-link-beautify-mode t))

;;; Code:

(require 'org) ; including `ol'
(require 'org-element)
(require 'org-element-ast)
(require 'cl-lib)
(require 'color)
(require 'faces)
(require 'image)
(require 'nerd-icons)
(require 'qrencode)

;; (require 'fb2-reader)
(declare-function fb2-reader--create-image "fb2-reader" (data type &rest props))
(declare-function fb2-reader--extract-image-data "fb2-reader" (book attributes &optional tags))
(declare-function fb2-reader--get-cover "fb2-reader" (book))
(declare-function fb2-reader-parse-file-as-html "fb2-reader" (file))
(declare-function fb2-reader-parse-file-as-xml "fb2-reader" (file))

;;; Customization
(defgroup org-link-beautify nil
  "Customize group of `org-link-beautify-mode'."
  :prefix "org-link-beautify-"
  :group 'org)

(defcustom olb/thumbnails-dir 'current-working-directory
  "The directory of generated thumbnails.

By default option value with symbol 'current-working-directory the
thumbnails are generated in source file path’s .thumbnails directory.
This is better for avoiding re-generate preview thumbnails. Or you can
set this option to 'user-home which represent to ~/.cache/thumbnails/."
  :type 'symbol
  :safe #'symbolp
  :group 'org-link-beautify)

(defcustom olb/enable-debug-p nil
  "Whether enable org-link-beautify print debug info."
  :type 'boolean
  :safe #'booleanp
  :group 'org-link-beautify)


;;; overlay keymap keybindings

(defvar olb/keymap
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map image-map) ; inherit `image-map' keybindings on preview thumbnail image.
    map))

(defun olb/action-goto-file-in-dired ()
  "Action of opening Dired and goto the link file position."
  (interactive)
  (when (derived-mode-p 'org-mode)
    (let* ((file-path (org-element-property :path (org-element-context)))
           (file-name (file-name-nondirectory file-path)))
      (org-attach-reveal)
      (search-forward file-name)
      (dired-move-to-filename) ; move point to beginning of filename.
      (if (and (featurep 'dwim-shell-command) (featurep 'dwim-shell-commands))
          (progn
            (message "Jumped to position of link file, now you can execute `dwim-shell-command' commands")
            (command-execute nil (read-extended-command-1 nil "dwim-shell-commands")))
        (user-error "Jumped to position of link file.
Package `dwim-shell-command' is missing, please install it")))))

(define-key olb/keymap (kbd "M-o") #'olb/action-goto-file-in-dired)

;; ;; NOTE: It will override all link type handlers.
;; (defun olb/action-browse-url (&optional link-str)
;;   "Visit the URL in LINK-STR with `browse-url'."
;;   (interactive)
;;   (let ((link-type (org-element-property :type (org-element-link-parser)))
;;         (link-raw (or link-str (org-element-property :raw-link (org-element-link-parser)))))
;;     (if (member link-type '("http" "https"))
;;         (browse-url link-raw)
;;       ;; `org-link-open-from-string'
;;       (org-link-open link-raw))))
;;
;; (define-key olb/keymap (kbd "C-o") #'olb/action-browse-url)

(defun olb/-copy-file-to-clipboard (file)
  "Copy the FILE on path to clipboard.
The argument FILE must be the absolute path."
  (cl-case system-type
    (darwin
     (do-applescript
      (format "tell app \"Finder\" to set the clipboard to ( POSIX file \"%s\" )" file)))
    (gnu/linux
     ;; - xclip-copyfile :: command copies files into the X clipboard, recursing into directories.
     ;; - xclip-cutfile :: command Copy the files, but also deletes them afterwards.
     ;; - xclip-pastefile :: command Paste the files out of the clipboard.
     ;; - xclip :: command Copy text or files to the clipboard.
     (if (executable-find "xclip-copyfile")
         (shell-command (format "xclip-copyfile %s" file))
       (user-error "[org-link-beautify] Error: the command-line tool 'xclip-copyfile' is not installed!")))
    ;; TODO:
    (windows-nt ))
  (message "Copied file [%s] to system clipboard" (string-truncate-left file (/ (window-width) 2))))

(defun olb/action-copy-file (&optional args)
  "Action of copying the Org link file at point with optional ARGS."
  (interactive "P")
  (when (derived-mode-p 'org-mode)
    (if (or (region-active-p) mark-active)
        (let ((region-text (buffer-substring-no-properties
                            (region-beginning) (region-end))))
          (kill-new region-text)
          (deactivate-mark))
      (let ((element (org-element-context)))
        (if (and (eq (car element) 'link)
                 (string-equal (org-element-property :type element) "file"))
            (let ((file-path (expand-file-name (org-element-property :path element))))
              (olb/-copy-file-to-clipboard file-path))
          (message "[org-link-beautify] No action executed on link"))))))

(define-key olb/keymap (kbd "M-w") #'olb/action-copy-file)

(defun olb/action-qrcode-for-url (&optional args)
  "Action of displaying QR code for Org link at point in new buffer in ARGS."
  (interactive)
  (when (derived-mode-p 'org-mode)
    (if-let* ((url (org-element-property-raw :raw-link (org-element-context))))
        (if (require 'qrencode nil t)
            (qrencode-string url)
          (package-install 'qrencode)
          (qrencode-string url))
      (if (or (region-active-p) mark-active)
          (org-fill-paragraph t t)
        (org-fill-paragraph)))))

(define-key olb/keymap (kbd "M-q") 'olb/action-qrcode-for-url)

;;; helper functions

(defun olb/-get-thumbnails-dir-path (file)
  "Return the FILE thumbnail directory's path."
  (if file
      (cl-case olb/thumbnails-dir
        (current-working-directory
         (concat (file-name-directory file) ".thumbnails/"))
        (user-home
         (expand-file-name "~/.cache/thumbnails/")))
    (user-error "[org-link-beautify] Error: the paramter `file' of function `org-link-beautify--get-thumbnails-dir-path' is nil")))

(defun olb/-ensure-thumbnails-dir (thumbnails-dir)
  "Ensure THUMBNAILS-DIR exist, if not ,create it."
  (if (file-exists-p (file-name-parent-directory thumbnails-dir))
      (unless (file-directory-p thumbnails-dir)
        (make-directory thumbnails-dir))
    (if (yes-or-no-p "[org-link-beautify] thumbnails directory parent directory does not exist, create it?")
        (make-directory thumbnails-dir t)
      (warn "[org-link-beautify] thumbnails directory parent directory does not exist"))))

(defun olb/-notify-generate-thumbnail-failed (source-file &optional _thumbnail-file)
  "Notify that generating THUMBNAIL-FILE for SOURCE-FILE failed."
  (message "[org-link-beautify] Failed to generate thumbnail for file %s" source-file))

(defun olb/-display-content-block (lines-list)
  "Display LINES-LIST string as a block with beautified frame border."
  (format
   "
┌%s┐
%s
└%s┘
\n"
   (make-string (- fill-column 2) ?─)
   (mapconcat
    (lambda (line)
      (concat "│ "
              (let* ((line-length-max (- fill-column 4))
                     (line-length (length line))
                     (line-text (if (< line-length line-length-max)
                                    line
                                  (let ((ellipsis (truncate-string-ellipsis)))
                                    (concat (truncate-string-to-width line (- line-length-max (length ellipsis))) ellipsis))))
                     (spaces (make-string
                              (if (< (length line-text) line-length-max)
                                  (- line-length-max (length line-text))
                                0)
                              ?\ )))
                (concat line-text spaces))
              " │"))
    lines-list
    "\n")
   (make-string (- fill-column 2) ?─)))

;; TEST:
;; (olb/-display-content-block '("hello world" "hello, name" "hello"))

(defun olb/-display-org-content (org-content)
  "Display ORG-CONTENT in `org-mode'."
  (with-temp-buffer
    (let ((org-startup-with-link-previews nil))
      (insert org-content)
      (org-mode)
      ;; (goto-char (line-beginning-position 2))
      ;; FIXME: how to fix org-attach directory issue.
      ;; error: "Need absolute ‘org-attach-id-dir’ to attach in buffers without filename"
      ;; reference `org-attach-dir'
      ;; (when (org-entry-get nil "DIR" org-attach-use-inheritance)
      ;;   (org-link-preview-region t t (point-min) (point-max)))
      (buffer-substring (point-min) (point-max)))))

;;; Invoke external Python script file or code.

(defcustom olb/python-interpreter (executable-find "python3")
  "Specify Python interpreter to run python scripts or code."
  :type 'string
  :safe #'stringp)

(defun olb/-python-script-run (python-script-file)
  "Run PYTHON-SCRIPT-FILE through shell command."
  (shell-command-to-string
   (format "%s %s" olb/python-interpreter python-script-file)))

(defun olb/-python-command-to-string (&rest code-lines)
  "Run Python CODE-LINES through shell command."
  (shell-command-to-string
   (concat "python -c "
           ;; solve double quote character issue.
           "\"" (string-replace "\"" "\\\"" (string-join code-lines "\n")) "\"")))

;; TEST:
;; (olb/-python-command-to-string
;;  "import numpy as np"
;;  "print(np.arange(6))"
;;  "print(\"blah blah\")"
;;  "print('{}'.format(3))")

;;; Invoke external JavaScript script file or code.

(defcustom olb/javascript-interpreter (executable-find "node")
  "Specify JavaScript interpreter to run JavaScript scripts or code."
  :type 'string
  :safe #'stringp)

(defun olb/-javascript-script-run (javascript-script-file)
  "Run JAVASCRIPT-SCRIPT-FILE through shell command."
  (shell-command-to-string
   (format "%s %s" olb/javascript-interpreter javascript-script-file)))

(defun olb/-javascript-command-to-string (&rest code-lines)
  "Run JavaScript CODE-LINES through shell command."
  (shell-command-to-string
   (concat olb/javascript-interpreter
           " --eval "
           ;; solve double quote character issue.
           "\"" (string-replace "\"" "\\\"" (string-join code-lines "\n")) "\"")))

;; TEST:
;; (olb/-javascript-command-to-string
;;  "console.log(\"hello, world!\");"
;;  "console.log(1 + 3);")

;;; Invoke external Ruby script file or code.

(defcustom olb/ruby-interpreter (executable-find "ruby")
  "Specify Ruby interpreter to run ruby scripts or code."
  :type 'string
  :safe #'stringp)

(defun olb/-ruby-script-run (ruby-script-file)
  "Run RUBY-SCRIPT-FILE through shell command."
  (shell-command-to-string
   (format "%s %s" olb/ruby-interpreter ruby-script-file)))

(defun olb/-ruby-command-to-string (&rest code-lines)
  "Run Ruby CODE-LINES through shell command."
  (shell-command-to-string
   (concat "ruby -e "
           ;; solve double quote character issue.
           "\"" (string-replace "\"" "\\\"" (string-join code-lines "\n")) "\"")))

;; TEST:
;; (olb/-ruby-command-to-string
;;  "puts 'hello, world'"
;;  (format "puts 'hello, %s'" user-full-name))

;;; Iconify for link

(defun olb/-get-link-description (position)
  "Get the link description at POSITION (fuzzy but faster version)."
  (save-excursion
    (goto-char position)
    (cond
     ((org-element-link-parser)
      (let ((link (org-element-link-parser)))
        (if (org-element-property :contents-begin link)
            (buffer-substring-no-properties
             (org-element-property :contents-begin link)
             (org-element-property :contents-end link))
          (org-element-property :raw-link link))))
     ((org-element-context)
      (let ((link (org-element-link-parser)))
        (org-element-property :raw-link link)))
     (t (save-excursion
          (goto-char position)
          (and (org-in-regexp org-link-bracket-re) (match-string 2)))))))

(defun olb/-return-warning-face (ov path link)
  "Return warning face if PATH does not exist on OV overlay at LINK element."
  (when (string-equal (org-element-property :type link) "file")
    (if (and (not (file-remote-p path))
             (file-exists-p (expand-file-name path)))
        'org-link
      'error)))

(defun olb/-return-icon (ov path link)
  "Return icon for PATH on OV overlay at LINK element."
  (let ((type (org-element-property :type link))
        (extension (file-name-extension path)))
    (pcase type
      ("file" (if-let* (extension (file-name-extension path))
                  (nerd-icons-icon-for-extension extension)
                (nerd-icons-icon-for-dir path)))
      ("attachment" (if-let* (extension (file-name-extension path))
                        (nerd-icons-icon-for-extension extension)
                      (nerd-icons-icon-for-dir path)))
      ("http" (nerd-icons-icon-for-url (concat type ":" path)))
      ("https" (nerd-icons-icon-for-url (concat type ":" path)))
      ("ftp" (nerd-icons-icon-for-url (concat type ":" path)))
      ;; Org mode internal link types
      ("custom-id" (nerd-icons-mdicon "nf-md-text_box_search_outline" :face 'nerd-icons-blue))
      ("id" (nerd-icons-mdicon "nf-md-text_search" :face 'nerd-icons-blue))
      ("coderef" (nerd-icons-codicon "nf-cod-references" :face 'nerd-icons-cyan))
      ("elisp" (nerd-icons-icon-for-file "file.el"))
      ("eshell" (nerd-icons-icon-for-mode 'eshell-mode))
      ("shell" (nerd-icons-icon-for-mode 'shell-mode))
      ("man" (nerd-icons-mdicon "nf-md-file_document_outline" :face 'nerd-icons-lblue))
      ("woman" (nerd-icons-mdicon "nf-md-file_document_outline" :face 'nerd-icons-blue-alt))
      ("info" (nerd-icons-mdicon "nf-md-information_outline" :face 'nerd-icons-lblue))
      ("help" (nerd-icons-mdicon "nf-md-help_circle_outline" :face 'nerd-icons-lblue))
      ("shortdoc" (nerd-icons-mdicon "nf-md-file_link" :face 'nerd-icons-blue))
      ;; org-ref link types
      ("cite" (nerd-icons-codicon "nf-cod-references" :face 'nerd-icons-cyan))
      ;; Org mode external link types
      ("eaf" (nerd-icons-mdicon "nf-md-apps" :face 'nerd-icons-blue)) ; emacs-application-framework
      ("eww" (nerd-icons-icon-for-mode 'eww-mode)) ; EWW
      ("chrome" (nerd-icons-mdicon "nf-md-google_chrome" :face 'nerd-icons-lorange))
      ("edge" (nerd-icons-mdicon "nf-md-microsoft_edge" :face 'nerd-icons-green))
      ("mu4e" (nerd-icons-mdicon "nf-md-email_search_outline" :face 'nerd-icons-blue))
      ("news" (nerd-icons-mdicon "nf-md-newspaper_variant_outline" :face 'nerd-icons-dgreen))
      ("git" (nerd-icons-mdicon "nf-md-git" :face 'nerd-icons-lred))
      ("orgit" (nerd-icons-faicon "nf-fa-git" :face 'nerd-icons-red))
      ("orgit-rev" (nerd-icons-devicon "nf-dev-git_commit" :face 'nerd-icons-silver))
      ("orgit-log" (nerd-icons-octicon "nf-oct-diff" :face 'nerd-icons-silver))
      ("pdf" (nerd-icons-faicon "nf-fa-file_pdf" :face 'nerd-icons-red))
      ("epub" (nerd-icons-mdicon "nf-md-book_open_page_variant_outline" :face 'nerd-icons-blue-alt))
      ("nov" (nerd-icons-icon-for-file "file.epub")) ; for Emacs package "nov.el" link type `nov:'
      ("grep" (nerd-icons-mdicon "nf-md-selection_search" :face 'nerd-icons-green))
      ("occur" (nerd-icons-mdicon "nf-md-selection_multiple" :face 'nerd-icons-green))
      ("rss" (nerd-icons-mdicon "nf-md-rss" :face 'nerd-icons-lorange))
      ("elfeed" (nerd-icons-mdicon "nf-md-rss" :face 'nerd-icons-green))
      ("wikipedia" (nerd-icons-mdicon "nf-md-wikipedia" :face 'nerd-icons-dsilver))
      ("mailto" (nerd-icons-mdicon "nf-md-email_send_outline" :face 'nerd-icons-lblue))
      ("irc" (nerd-icons-mdicon "nf-md-chat" :face 'nerd-icons-blue-alt))
      ("wechat" (nerd-icons-mdicon "nf-md-wechat" :face 'nerd-icons-green))
      ("magnet" (nerd-icons-mdicon "nf-md-magnet" :face 'nerd-icons-blue-alt))
      ("ref" (nerd-icons-codicon "nf-cod-references" :face 'nerd-icons-blue))
      ("doi" (nerd-icons-mdicon "nf-md-file_document_plus_outline" :face 'nerd-icons-green))
      ("org-contact" (nerd-icons-mdicon "nf-md-contacts_outline" :face 'nerd-icons-purple-alt))
      ("org-bookmark" (nerd-icons-mdicon "nf-md-bookmark_check_outline" :face 'nerd-icons-blue-alt))
      ("org-ql-search" (nerd-icons-mdicon "nf-md-text_box_search_outline" :face 'nerd-icons-blue-alt))
      ;; org-media-note link types
      ("video" (nerd-icons-faicon "nf-fa-file_video_o" :face 'nerd-icons-blue))
      ("audio" (nerd-icons-faicon "nf-fa-file_audio_o" :face 'nerd-icons-blue))
      ("videocite" (nerd-icons-faicon "nf-fa-file_video_o" :face 'nerd-icons-blue-alt))
      ("audiocite" (nerd-icons-faicon "nf-fa-file_audio_o" :face 'nerd-icons-blue-alt))
      ("javascript" (nerd-icons-mdicon "nf-md-language_javascript" :face 'nerd-icons-yellow))
      ("js" (nerd-icons-mdicon "nf-md-language_javascript" :face 'nerd-icons-yellow))
      ("vscode" (nerd-icons-mdicon "nf-md-microsoft_visual_studio_code" :face 'nerd-icons-blue-alt)) ; Visual Studio Code
      ("macappstore" (nerd-icons-mdicon "nf-md-apple" :face 'nerd-icons-blue)) ; Mac App Store
      
      ("fuzzy"
       ;; Org internal [[reference][reference]] -> NOT supported by:
       ;; `(org-link-set-parameters link-type :activate-func ...)'
       ;;
       ;; (link (:standard-properties [584419 nil 584470 584517 584519 0 nil nil nil nil nil nil ...] :type "fuzzy" :type-explicit-p nil :path "defcustom org-contacts-identity-properties-list" :format bracket :raw-link "defcustom org-contacts-identity-properties-list" ...))
       
       (when-let* ((_ (string-match "\\([^:]*\\):\\(.*\\)" path))
                   (real-type (match-string 1 path))) ; extract the "real" link type for "fuzzy" type in :path.
         (cond
          (t
           (message "[org-link-beautify] link type not supported, add PR for this link type.
type: %s, path: %s, extension: %s, link-element: %s" type path extension link)
           (nerd-icons-mdicon "nf-md-progress_question" :face 'nerd-icons-lyellow)))))
      (_
       (message "[org-link-beautify] link type not supported, add PR for this link type.
type: %s, path: %s, extension: %s, link-element: %s" type path extension link)
       ;; handle when returned link type is `nil'.
       (nerd-icons-mdicon "nf-md-progress_question" :face 'nerd-icons-lyellow)))))

(defun olb/iconify (ov path link)
  "Iconify PATH over OV overlay position for LINK element."
  (when-let* ((begin (org-element-begin link))
              (end (org-element-end link))
              (description (olb/-get-link-description begin))
              (icon (olb/-return-icon ov path link)))
    (unless (overlay-get ov 'org-image-overlay)
      (overlay-put ov
                   'display (concat
                             (propertize "["
                                         'face `( :inherit 'default
                                                  :underline t
                                                  :foreground ,(if (face-foreground 'shadow)
                                                                   (color-lighten-name (face-foreground 'shadow) 2)
                                                                 "gray40")))
                             (propertize description
                                         'face (olb/-return-warning-face ov path link)
                                         'read-only t 'inhibit-isearch t 'intangible t)
                             (propertize "]"
                                         'face `( :inherit 'default
                                                  :underline t
                                                  :foreground ,(if (face-foreground 'shadow)
                                                                   (color-lighten-name (face-foreground 'shadow) 2)
                                                                 "gray40")))))
      (overlay-put ov
                   'after-string (concat
                                  (propertize "[" 'face '(:inherit 'default :foreground "orange"))
                                  icon
                                  ;; (propertize icon 'face '(:slant 'normal))
                                  (propertize "]" 'face '(:inherit 'default :foreground "orange"))))
      (overlay-put ov 'keymap  olb/keymap))
    t))

;;; General thumbnail generator with Python "thumbnail.py" library.

(defvar olb/thumbnailer-script
  (expand-file-name "scripts/thumbnailer.py" (file-name-directory (or load-file-name (buffer-file-name))))
  "The path of general thumbnailer script.")

(defun olb/thumbnailer (path)
  "Generate thumbnail image for file of PATH over OV overlay position for LINK element."
  (when (string-match "\\(.*?\\)\\(?:::\\(.*\\)\\)?\\'" path)
    (let* ((file-path (match-string 1 path))
           (input-file (expand-file-name (org-link-unescape file-path)))
           (search-option (match-string 2 path))
           (thumbnails-dir (olb/-get-thumbnails-dir-path input-file))
           (thumbnail-file (expand-file-name (format "%s%s.png" thumbnails-dir (file-name-base input-file))))
           (thumbnail-size 600))
      (unless (file-exists-p thumbnail-file)
        (let* ((proc-name (format "org-link-beautify thumbnailer - %s" (file-name-base input-file)))
               (proc-buffer (format " *org-link-beautify thumbnailer - %s*" (file-name-base input-file)))
               (proc (get-process proc-name)))
          (make-process
           :name proc-name
           :command (list olb/thumbnailer-script
                          input-file
                          thumbnail-file
                          (number-to-string thumbnail-size))
           :buffer proc-buffer
           :stderr nil ; If STDERR is nil, standard error is mixed with standard output and sent to BUFFER or FILTER.
           :sentinel (lambda (proc event)
                       (when olb/enable-debug-p
                         ;; DEBUG:
                         (message (format "> proc: %s\n> event: %s" proc event)))
                       ;; (when (string= event "finished\n")
                       ;;   (kill-buffer (process-buffer proc))
                       ;;   (kill-process proc))
                       ))))
      ;; return the thumbnail file as result.
      thumbnail-file)))

(defun olb/overlay-display-image (ov image &optional align)
  "Display IMAGE object on overlay OV in ALIGN position.
The IMAGE object is created by `create-image' from `org--create-inline-image'."
  ;; See bug#59902. We cannot rely on Emacs to update image if the file has changed.
  (image-flush image) ; refresh image in cache if file changed.
  (image--set-property image :mask 'heuristic)
  (overlay-put ov 'display image)
  (overlay-put ov 'face    'default)
  (overlay-put ov 'keymap  olb/keymap)
  (when align
    (overlay-put ov
                 'before-string (propertize " "
                                            'face 'default
                                            'display (pcase align
                                                       ("center" `(space :align-to (- center (0.5 . ,image))))
                                                       ("right"  `(space :align-to (- right ,image)))))))
  t)

(defun olb/preview-thumbnail (ov path link)
  "Display thumbnail on overlay OV from PATH at element LINK."
  (if-let* ((_ (display-graphic-p))
            (thumbnail-file (olb/thumbnailer path))
            ;; ((string-match-p (image-file-name-regexp) thumbnail-file))
            ( (file-exists-p thumbnail-file)))
      (let* ((width (or (org-display-inline-image--width link) 300))
             (align (org-image--align link))
             (image (org--create-inline-image thumbnail-file width)))
        (if image                     ; Add image to overlay
	        (olb/overlay-display-image ov image align)
          nil))))

;;; Preview file: link type

(defun olb/preview-file (ov path link)
  "Preview file of PATH over OV overlay position for LINK element.
This function will apply file type function based on file extension."
  (if-let* ((extension (file-name-extension path)))
      (cond
       ((null extension) ; no file extension, it's directory.
        (olb/iconify ov path link))
       ((string-match-p (image-file-name-regexp) path) ; `olb/image-preview-list'
        (olb/preview-file-image ov path link))
       ((string-equal extension "pdf")
        (olb/preview-file-pdf ov path link))
       ((string-equal extension "epub")
        (olb/preview-file-epub ov path link))
       ((string-match-p "\\(mobi\\|azw3\\)" extension)
        (olb/preview-file-kindle ov path link))
       ((string-match-p "\\.fb2\\(\\.zip\\)?" path)
        (olb/preview-file-fictionbook2 ov path link))
       ((member extension olb/comic-preview-list)
        (olb/preview-file-comic ov path link))
       ((member extension olb/video-preview-list)
        (olb/preview-file-video ov path link))
       ((member extension olb/audio-preview-list)
        (olb/preview-file-audio ov path link))
       ((member extension olb/subtitle-preview-list)
        (olb/preview-file-subtitle ov path link))
       ((member extension olb/archive-preview-list)
        (olb/preview-file-archive ov path link))
       ((member extension olb/source-code-preview-list)
        (olb/preview-file-source-code ov path link))
       (t (or (olb/preview-thumbnail ov path link)
              (olb/iconify ov path link))))))

;;; Preview attachment: link type

(defun olb/preview-attachment (ov path link)
  "Preview attachment file of PATH over OV overlay position for LINK element.
This function will apply file type function based on file extension."
  (org-with-point-at (org-element-begin link)
    (olb/preview-file ov (org-attach-expand path) link)))

;;; file: [image]

(defcustom olb/image-preview-list
  '("jpg" "jpeg" "png" "gif" "webp")
  "A list of image file types be supported with thumbnails."
  :type 'list
  :safe #'listp
  :group 'org-link-beautify)

(defun olb/preview-file-image (ov path link)
  "Preview image file of PATH over OV overlay position for LINK element."
  (if-let* (( (display-graphic-p))
            (file (expand-file-name path))
            ;; ((string-match-p (image-file-name-regexp) file))
            ( (file-exists-p file)))
      (let* ((align (org-image--align link))
             (width (org-display-inline-image--width link))
             (image (org--create-inline-image file width)))
        (if image                     ; Add image to overlay
	        ;; See bug#59902. We cannot rely on Emacs to update image if the file has changed.
            (olb/overlay-display-image ov image align)
          nil))))

;;; file: .pdf

(defcustom olb/pdf-preview-command
  (cond
   ((executable-find "pdftocairo") "pdftocairo")
   ((executable-find "pdf2svg") "pdf2svg"))
  "The command used to preview PDF file cover."
  :type 'string
  :safe #'stringp
  :group 'org-link-beautify)

(defcustom olb/pdf-preview-size 300
  "The PDF preview image size."
  :type 'number
  :safe #'numberp
  :group 'org-link-beautify)

(defcustom olb/pdf-preview-default-page-number 1
  "The default PDF preview page number."
  :type 'number
  :safe #'numberp
  :group 'org-link-beautify)

(defcustom olb/pdf-preview-image-format 'png
  "The format of PDF file preview image."
  :type '(choice
          :tag "The format of PDF file preview image."
          (const :tag "PNG" png)
          (const :tag "JPEG" jpeg)
          (const :tag "SVG" svg))
  :safe #'symbolp
  :group 'org-link-beautify)

(defun olb/-generate-preview-for-file-pdf (path)
  "Generate THUMBNAIL-FILE with THUMBNAIL-SIZE for .pdf file of PATH."
  (when (string-match "\\(.*?\\)\\(?:::\\(.*\\)\\)?\\'" path)
    (let* ((file-path (match-string 1 path))
           (search-option (match-string 2 path))
           (pdf-page-number (if search-option
                                (string-to-number
                                 (cond
                                  ((string-prefix-p "P" search-option) ; "P42"
                                   (substring search-option 1 nil))
                                  ((string-match "\\([[:digit:]]+\\)\\+\\+\\(.*\\)" search-option) ; "40++0.00"
                                   (match-string 1 search-option))
                                  (t search-option)))
                              (if-let* ((search-option (match-string 2 path)))
                                  (string-to-number
                                   (cond
                                    ((string-prefix-p "P" search-option) ; "P42"
                                     (substring search-option 1 nil))
                                    ((string-match "\\([[:digit:]]+\\)\\+\\+\\(.*\\)" search-option) ; "40++0.00"
                                     (match-string 1 search-option))
                                    (t search-option)))
                                olb/pdf-preview-default-page-number)))
           (pdf-file (expand-file-name (org-link-unescape file-path)))
           (thumbnails-dir (olb/-get-thumbnails-dir-path pdf-file))
           (thumbnail-file (expand-file-name
                            (if (= pdf-page-number 1) ; if have page number ::N specified.
                                (format "%s%s.%s"
                                        thumbnails-dir (file-name-base pdf-file)
                                        (symbol-name olb/pdf-preview-image-format))
                              (format "%s%s-P%s.%s"
                                      thumbnails-dir (file-name-base pdf-file) pdf-page-number
                                      (symbol-name olb/pdf-preview-image-format)))))
           (thumbnail-size 600)
           (proc-name (format "org-link-beautify pdf preview - %s" pdf-file))
           (proc-buffer (format " *org-link-beautify pdf preview - %s*" pdf-file))
           (proc (get-process proc-name)))
      (olb/-ensure-thumbnails-dir thumbnails-dir)
      (unless (file-exists-p thumbnail-file)
        (pcase (file-name-nondirectory olb/pdf-preview-command)
          ("pdftocairo"
           (start-process
            proc-name proc-buffer
            "pdftocairo"
            (pcase olb/pdf-preview-image-format
              ('png "-png")
              ('jpeg "-jpeg")
              ('svg "-svg"))
            "-singlefile"
            "-f" (number-to-string pdf-page-number)
            pdf-file (file-name-sans-extension thumbnail-file)))
          ("pdf2svg"
           (unless (eq olb/pdf-preview-image-format 'svg)
             (warn "The pdf2svg only supports convert PDF to SVG format.
Please adjust `org-link-beautify-pdf-preview-command' to `pdftocairo' or
Set `org-link-beautify-pdf-preview-image-format' to `svg'."))
           (start-process
            proc-name proc-buffer
            "pdf2svg" pdf-file thumbnail-file (number-to-string pdf-page-number)))))
      (when (and olb/enable-debug-p (not (file-exists-p thumbnail-file)))
        (olb/-notify-generate-thumbnail-failed path thumbnail-file))
      ;; return the thumbnail file as result.
      thumbnail-file)))

(defun olb/preview-file-pdf (ov path link)
  "Preview pdf file of PATH over OV overlay position for LINK element."
  (if-let* (( (display-graphic-p))
            (olb/pdf-preview-command)
            (thumbnail-file (olb/-generate-preview-for-file-pdf path))
            ((file-exists-p thumbnail-file))
            ;; NOTE: limite thumbnail image inline display width to hardcoded 300.
            (width (or 300 (org-display-inline-image--width link) olb/pdf-preview-size))
            (image (org--create-inline-image thumbnail-file width)))
      (prog1 ov
        (olb/overlay-display-image ov image))
    (olb/iconify ov path link)))

;;; file: .epub

(defcustom olb/epub-preview-command
  (let ((script (expand-file-name "scripts/thumbnailer-epub.py" (file-name-directory (or load-file-name (buffer-file-name))))))
    (cl-case system-type
      (gnu/linux (if (executable-find "gnome-epub-thumbnailer")
                     "gnome-epub-thumbnailer"
                   script))
      (darwin (if (executable-find "epub-thumbnailer")
                  "epub-thumbnailer"
                script))
      (t script)))
  "Whether enable EPUB files cover preview?
If command \"gnome-epub-thumbnailer\" is available, enable EPUB
preview by default. You can set this option to nil to disable
EPUB preview."
  :type 'string
  :safe #'stringp
  :group 'org-link-beautify)

(defcustom olb/ebook-preview-size 600
  "The EPUB cover preview image size."
  :type 'number
  :safe #'numberp
  :group 'org-link-beautify)

(defun olb/-generate-preview-for-file-epub (path)
  "Generate THUMBNAIL-FILE with THUMBNAIL-SIZE for .epub file of PATH."
  (when (string-match "\\(.*?\\)\\(?:::\\(.*\\)\\)?\\'" path)
    (let* ((file-path (match-string 1 path))
           (search-option (match-string 2 path))
           ;; TODO: currently epub file page number thumbnail is not supported by `org-link-beautify-epub-preview-command'.
           (epub-page-number (if search-option (string-to-number search-option) 1))
           (epub-file (expand-file-name (org-link-unescape file-path)))
           (thumbnails-dir (olb/-get-thumbnails-dir-path epub-file))
           (thumbnail-file (expand-file-name
                            (if (or (null epub-page-number) (= epub-page-number 1)) ; if have page number ::N specified.
                                (format "%s%s.png" thumbnails-dir (file-name-base epub-file))
                              (format "%s%s-P%s.png" thumbnails-dir (file-name-base epub-file) epub-page-number))))
           (thumbnail-size (or olb/ebook-preview-size 600))
           (proc-name (format "org-link-beautify epub preview - %s" epub-file))
           (proc-buffer (format " *org-link-beautify epub preview - %s*" epub-file))
           (proc (get-process proc-name)))
      (olb/-ensure-thumbnails-dir thumbnails-dir)
      (unless (file-exists-p thumbnail-file)
        (pcase (file-name-nondirectory olb/epub-preview-command)
          ("epub-thumbnailer"           ; for macOS command "epub-thumbnailer"
           (make-process
            :name proc-name
            :command (list olb/epub-preview-command
                           epub-file
                           thumbnail-file
                           (number-to-string thumbnail-size))
            :buffer proc-buffer
            :stderr nil ; If STDERR is nil, standard error is mixed with standard output and sent to BUFFER or FILTER.
            :sentinel (lambda (proc event)
                        (if olb/enable-debug-p
                            (message (format "> proc: %s\n> event: %s" proc event))
                          ;; (when (string= event "finished\n")
                          ;;   (kill-buffer (process-buffer proc))
                          ;;   (kill-process proc))
                          ))))
          ("thumbnailer-epub.py"           ; for script "scripts/epub-thumbnailer.py"
           (make-process
            :name proc-name
            :command (list olb/python-interpreter
                           olb/epub-preview-command
                           epub-file
                           thumbnail-file
                           (number-to-string thumbnail-size))
            :buffer proc-buffer
            :stderr nil ; If STDERR is nil, standard error is mixed with standard output and sent to BUFFER or FILTER.
            :sentinel (lambda (proc event)
                        (if olb/enable-debug-p
                            (message (format "> proc: %s\n> event: %s" proc event))
                          ;; (when (string= event "finished\n")
                          ;;   (kill-buffer (process-buffer proc))
                          ;;   (kill-process proc))
                          ))))
          ("gnome-epub-thumbnailer"                 ; for Linux "gnome-epub-thumbnailer"
           (start-process
            proc-name proc-buffer
            olb/epub-preview-command
            epub-file thumbnail-file
            (when olb/ebook-preview-size "--size")
            (when olb/ebook-preview-size (number-to-string thumbnail-size))))
          (_ (user-error "This system platform currently not supported by org-link-beautify.\n Please contribute code to support"))))
      (when (and olb/enable-debug-p (not (file-exists-p thumbnail-file)))
        (olb/-notify-generate-thumbnail-failed epub-file thumbnail-file))
      ;; return the thumbnail file as result.
      thumbnail-file)))

(defun olb/preview-file-epub (ov path link)
  "Preview epub file of PATH over OV overlay position for LINK element."
  (if-let* (( (display-graphic-p))
            (olb/epub-preview-command)
            (thumbnail-file (olb/-generate-preview-for-file-epub path))
            ((file-exists-p thumbnail-file))
            ;; NOTE: limite thumbnail image inline display width to hardcoded 300.
            (width (or 300 (org-display-inline-image--width link) olb/ebook-preview-size))
            (image (org--create-inline-image thumbnail-file width)))
      (prog1 ov
        (olb/overlay-display-image ov image))
    (olb/iconify ov path link)))

;;; file: .mobi, .azw3

(defcustom olb/kindle-preview-command
  (cl-case system-type
    (gnu/linux (executable-find "mobitool"))
    (darwin (executable-find "mobitool")))
  "Whether enable Kindle ebook files cover preview?

Enable Kindle ebook preview by default.

You can set this option to nil to disable EPUB preview.

You can install software `libmobi' to get command `mobitool'."
  :type 'string
  :safe #'stringp
  :group 'org-link-beautify)

(defcustom olb/kindle-preview-size 300
  "The Kindle cover preview image size."
  :type 'number
  :safe #'numberp
  :group 'org-link-beautify)

(defun olb/-generate-preview-for-file-kindle (path)
  "Generate THUMBNAIL-FILE with THUMBNAIL-SIZE for .mobi & .azw3 file of PATH."
  (when (string-match "\\(.*?\\)\\(?:::\\(.*\\)\\)?\\'" path)
    (let* ((file-path (match-string 1 path))
           (kindle-page-number (or (match-string 2 path) 1))
           (kindle-file (expand-file-name (org-link-unescape file-path)))
           (thumbnails-dir (olb/-get-thumbnails-dir-path kindle-file))
           (thumbnail-file (expand-file-name
                            (if (or (null kindle-page-number) (= kindle-page-number 1)) ; if have page number ::N specified.
                                (format "%s%s.jpg" thumbnails-dir (file-name-base kindle-file))
                              (format "%s%s-P%s.jpg" thumbnails-dir (file-name-base kindle-file) kindle-page-number))))
           (thumbnail-size (or olb/ebook-preview-size 600))
           (proc-name (format "org-link-beautify kindle preview - %s" kindle-file))
           (proc-buffer (format " *org-link-beautify kindle preview - %s*" kindle-file))
           (proc (get-process proc-name)))
      (olb/-ensure-thumbnails-dir thumbnails-dir)
      (unless (file-exists-p thumbnail-file)
        (pcase (file-name-nondirectory olb/kindle-preview-command)
          ("mobitool"
           ;; mobitool dumped cover image thumbnail filename can't be specified in command-line argument.
           (let ((mobitool-cover-file (concat thumbnails-dir (file-name-base kindle-file) "_cover.jpg")))
             (unless (file-exists-p mobitool-cover-file)
               (start-process
                proc-name proc-buffer
                "mobitool" "-c" "-o" thumbnails-dir kindle-file))
             ;; then rename [file.extension.jpg] to [file.jpg]
             (when (file-exists-p mobitool-cover-file)
               (rename-file mobitool-cover-file thumbnail-file))))
          (_ (user-error "[org-link-beautify] Error: Can't find command tool to dump kindle ebook file cover"))))
      (when (and olb/enable-debug-p (not (file-exists-p thumbnail-file)))
        (olb/-notify-generate-thumbnail-failed kindle-file thumbnail-file))
      ;; return the thumbnail file as result.
      thumbnail-file)))

(defun olb/preview-file-kindle (ov path link)
  "Preview kindle .mobi or .azw3 file of PATH over OV overlay position for LINK element."
  (if-let* (( (display-graphic-p))
            (olb/kindle-preview-command)
            (thumbnail-file (olb/-generate-preview-for-file-kindle path))
            ((file-exists-p thumbnail-file))
            ;; NOTE: limite epub file thumbnail image inline display width to hardcoded 300.
            (width (or 300 (org-display-inline-image--width link)))
            (image (org--create-inline-image thumbnail-file width)))
      (prog1 ov
        (olb/overlay-display-image ov image))
    (olb/iconify ov path link)))

;;; FictionBook2 (.fb2, .fb2.zip) file cover preview

(defcustom olb/fictionbook2-preview (featurep 'fb2-reader)
  "Whether enable FictionBook2 ebook files covert preview?"
  :type 'boolean
  :safe #'booleanp
  :group 'org-link-beautify)

(defcustom olb/fictionbook2-preview-size 300
  "The FictionBook2 cover preview image size."
  :type 'number
  :safe #'numberp
  :group 'org-link-beautify)

(defun olb/fictionbook2--extract-cover (file-path)
  "Extract cover image data for FictionBook2 at FILE-PATH."
  (if-let* (;; reference `fb2-reader-mode'
            (book (or (fb2-reader-parse-file-as-xml file-path)
                      (fb2-reader-parse-file-as-html file-path)))
            ;; reference `fb2-reader-splash-screen'
            (cover-item (fb2-reader--get-cover book))
            ;; reference `fb2-reader-splash-cover': (fb2-reader-splash-cover book cover-item)
            (attrs (cl-second (cl-third cover-item)))
            (img-data (fb2-reader--extract-image-data book attrs))
            (type (cl-first img-data))
            (data (cl-second img-data))
            ;; reference `fb2-reader--insert-image': (fb2-reader--insert-image data-str type-str nil t)
            (type-symbol (alist-get type '(("image/jpeg" . jpeg) ("image/png" . png)) nil nil 'equal))
            (data-decoded (base64-decode-string data))
            (img-raw (fb2-reader--create-image data-decoded type-symbol))
            (image (create-image data-decoded type-symbol 't)))
      image
    'no-cover))

(defun olb/fictionbook2--save-cover (image thumbnail-file)
  "Save FictionBook2 cover IMAGE to THUMBNAIL-FILE."
  ;; `image-save': This writes the original image data to a file.
  (with-temp-buffer
    (insert (plist-get (cdr image) :data))
    (write-region (point-min) (point-max) thumbnail-file)))

(defun olb/-generate-preview-for-file-fictionbook2 (path)
  "Generate THUMBNAIL-FILE with THUMBNAIL-SIZE for .fb2 & .fb2.zip file of PATH."
  (when (string-match "\\(.*?\\)\\(?:::\\(.*\\)\\)?\\'" path)
    (let* ((file-path (match-string 1 path))
           (search-option (match-string 2 path))
           (fictionbook2-file (expand-file-name (org-link-unescape file-path)))
           (thumbnails-dir (olb/-get-thumbnails-dir-path fictionbook2-file))
           (thumbnail-file (cond
                            ((string-match-p "\\.fb2.zip$" path)
                             (expand-file-name
                              (format "%s%s.png" thumbnails-dir (string-replace ".fb2" "" (file-name-base fictionbook2-file)))))
                            ((string-match-p "\\.fb2$" path)
                             (expand-file-name (format "%s%s.png" thumbnails-dir (file-name-base fictionbook2-file))))))
           (thumbnail-size (or olb/fictionbook2-preview-size 600))
           (proc-name (format "org-link-beautify fictionbook preview - %s" fictionbook2-file))
           (proc-buffer (format " *org-link-beautify fictionbook preview - %s*" fictionbook2-file))
           (proc (get-process proc-name)))
      (olb/-ensure-thumbnails-dir thumbnails-dir)
      (unless (file-exists-p thumbnail-file)
        (let ((cover-image (olb/fictionbook2--extract-cover fictionbook2-file)))
          (if (eq cover-image 'no-cover)
              (message "[org-link-beautify] FictionBook2 preview failed to extract cover image")
            (olb/fictionbook2--save-cover cover-image thumbnail-file))))
      (when (and olb/enable-debug-p (not (file-exists-p thumbnail-file)))
        (olb/-notify-generate-thumbnail-failed fictionbook2-file thumbnail-file))
      ;; return the thumbnail file as result.
      thumbnail-file)))

(defun olb/preview-file-fictionbook2 (ov path link)
  "Preview FictionBook2 .fb2, .fb2.zip file of PATH over OV overlay position for LINK element."
  (if-let* ((olb/fictionbook2-preview)
            ( (display-graphic-p))
            (thumbnail-file (olb/-generate-preview-for-file-fictionbook2 path))
            ((file-exists-p thumbnail-file))
            ;; NOTE: limite thumbnail image inline display width to hardcoded 300.
            (width (or 300 (org-display-inline-image--width link)))
            (image (org--create-inline-image thumbnail-file width)))
      (prog1 ov
        (olb/overlay-display-image ov image))
    (olb/iconify ov path link)))

;;; Source Code File

(defcustom olb/source-code-preview-command
  (cond
   ((executable-find "silicon") "silicon")
   ((executable-find "germanium") "germanium"))
  "The command used to preview source code file."
  :type 'string
  :safe #'stringp
  :group 'org-link-beautify)

(defcustom olb/source-code-preview-list
  '(; "org" "txt" "markdown" "md"
    "lisp" "scm" "clj" "cljs"
    "py" "rb" "pl"
    "c" "cpp" "h" "hpp" "cs" "java"
    "js" "css"
    "R" "jl")
  "A list of link types supports source code file preview below the link."
  :type 'list
  :safe #'listp
  :group 'org-link-beautify)

(defcustom olb/source-code-preview-max-lines 30
  "The maximum lines number of file for previewing."
  :type 'number
  :safe #'numberp
  :group 'org-link-beautify)

(defun olb/-preview-source-code-file (file)
  "Return first 10 lines of FILE."
  (with-temp-buffer
    (condition-case nil
        (progn
          ;; I originally use `insert-file-contents-literally', so Emacs doesn't
          ;; decode the non-ASCII characters it reads from the file, i.e. it
          ;; doesn't interpret the byte sequences as Chinese characters. Use
          ;; `insert-file-contents' instead. In addition, this function decodes
          ;; the inserted text from known formats by calling format-decode,
          ;; which see.
          (insert-file-contents file)
          (olb/-display-content-block
           ;; This `cl-loop' extract a LIST of string lines from the file content.
           (cl-loop repeat 10
                    unless (eobp)
                    collect (prog1 (buffer-substring-no-properties
                                    (line-beginning-position)
                                    (line-end-position))
                              (forward-line 1)))))
      (file-error
       (message "Unable to read file %S" file)
	   nil))))

(defun olb/-generate-preview-for-file-source-code (path)
  "Generate THUMBNAIL-FILE with THUMBNAIL-SIZE for source code file of PATH."
  (when (string-match "\\(.*?\\)\\(?:::\\(.*\\)\\)?\\'" path)
    (let* ((file-path (match-string 1 path))
           (search-option (match-string 2 path))
           (source-code-file (expand-file-name (org-link-unescape file-path)))
           (thumbnails-dir (olb/-get-thumbnails-dir-path source-code-file))
           (thumbnail-file (expand-file-name (format "%s%s.png" thumbnails-dir (file-name-base source-code-file))))
           (thumbnail-size 600)
           (proc-name (format "org-link-beautify code preview - %s" source-code-file))
           (proc-buffer (format " *org-link-beautify code preview - %s*" source-code-file))
           (proc (get-process proc-name)))
      (olb/-ensure-thumbnails-dir thumbnails-dir)
      (unless (and (file-exists-p thumbnail-file)
                   ;; limit to maximum 30 lines of file.
                   (> (string-to-number (shell-command-to-string (format "cat %s | wc -l" source-code-file)))
                      olb/source-code-preview-max-lines))
        (unless proc
          (pcase (file-name-nondirectory olb/source-code-preview-command)
            ("silicon"
             (start-process
              proc-name proc-buffer
              "silicon" source-code-file "-o" thumbnail-file
              "--theme" "Dracula"
              "--no-window-controls" "--shadow-blur-radius" "30" "--shadow-color" "#555"
              "--window-title" (file-name-nondirectory file-path)))
            ("germanium"
             (start-process
              proc-name proc-buffer
              "germanium" source-code-file "-o" thumbnail-file
              "--no-line-number" "--no-window-access-bar")))))
      (when (and olb/enable-debug-p (not (file-exists-p thumbnail-file)))
        (olb/-notify-generate-thumbnail-failed fictionbook2-file thumbnail-file))
      ;; return the thumbnail file as result.
      thumbnail-file)))

(defun olb/preview-file-source-code (ov path link)
  "Preview source code file of PATH over OV overlay position for LINK element."
  (if-let* (( (display-graphic-p))
            (olb/source-code-preview-command)
            (thumbnail-file (olb/-generate-preview-for-file-source-code path))
            ((file-exists-p thumbnail-file))
            (image (create-image thumbnail-file nil nil :width 800)))
      (prog1 ov
        (olb/overlay-display-image ov image))
    (if-let* ((source-code (olb/-preview-source-code-file path)))
        (prog1 ov
          (overlay-put ov 'after-string source-code)
	      (overlay-put ov 'face    'org-block))
      (olb/iconify ov path link))))

;;; file: [comic]

(defcustom olb/comic-preview-command
  (cl-case system-type
    (darwin (or (executable-find "qlmanage") olb/thumbnailer-script))
    (gnu/linux olb/thumbnailer-script))
  "Whether enable CDisplay Archived Comic Book Formats cover preview.
File extensions like (.cbr, .cbz, .cb7, .cba, .cbt etc)."
  :type 'string
  :safe #'stringp
  :group 'org-link-beautify)

(defcustom olb/comic-preview-list
  '("cbr" "cbz" "cb7" "cba" "cbt")
  "A list of comic file types be supported with thumbnails."
  :type 'list
  :safe #'listp
  :group 'org-link-beautify)

(defcustom olb/comic-preview-size 500
  "The CDisplay Archived Comic Book Formats cover preview image size."
  :type 'number
  :safe #'numberp
  :group 'org-link-beautify)

(defun olb/-generate-preview-for-file-comic (path)
  "Generate THUMBNAIL-FILE with THUMBNAIL-SIZE for CDisplay Archived Comic Book: .cbz, .cbr etc file of PATH."
  (when (string-match "\\(.*?\\)\\(?:::\\(.*\\)\\)?\\'" path)
    (let* ((file-path (match-string 1 path))
           (comic-file (expand-file-name (org-link-unescape file-path)))
           (thumbnails-dir (olb/-get-thumbnails-dir-path comic-file))
           (thumbnail-file (expand-file-name (format "%s%s.png" thumbnails-dir (file-name-base comic-file))))
           (thumbnail-size (or olb/comic-preview-size 1080))
           (proc-name (format "org-link-beautify comic preview - %s" (file-name-base file-path)))
           (proc-buffer (format " *org-link-beautify comic preview - %s*" (file-name-base file-path)))
           (proc (get-process proc-name)))
      (olb/-ensure-thumbnails-dir thumbnails-dir)
      (unless (file-exists-p thumbnail-file)
        (unless proc
          (cl-case system-type
            (gnu/linux
             (pcase (file-name-nondirectory olb/comic-preview-command)
               ("cbconvert"              ; https://github.com/gen2brain/cbconvert
                (start-process
                 proc-name
                 proc-buffer
                 olb/comic-preview-command
                 "cover" comic-file "--output" thumbnails-dir
                 (if olb/comic-preview-size
                     "--width")
                 (if olb/comic-preview-size
                     (number-to-string thumbnail-size))))
               ("thumbnailer.py" (olb/thumbnailer file-path))))
            (darwin
             ;; for macOS "qlmanage" command
             ;; $ qlmanage -t "ラセン恐怖閣-マリコとニジロー1-DL版.cbz" - 2.0 -s 1080 -o ".thumbnails"
             (pcase (file-name-nondirectory olb/comic-preview-command)
               ("qlmanage"
                (let ((qlmanage-thumbnail-file (concat thumbnails-dir (file-name-nondirectory comic-file) ".png")))
                  (make-process
                   :name proc-name
                   :command (list olb/comic-preview-command
                                  "-t"
                                  comic-file
                                  "-o" thumbnails-dir
                                  "-s" (number-to-string thumbnail-size))
                   :buffer proc-buffer
                   :stderr nil ; If STDERR is nil, standard error is mixed with standard output and sent to BUFFER or FILTER.
                   :sentinel (lambda (proc event)
                               (if olb/enable-debug-p
                                   (message (format "> proc: %s\n> event: %s" proc event))
                                 ;; (when (string= event "finished\n")
                                 ;;   (kill-buffer (process-buffer proc))
                                 ;;   (kill-process proc))
                                 )))
                  ;; then rename [file.extension.png] to [file.png]
                  (when (file-exists-p qlmanage-thumbnail-file)
                    (rename-file qlmanage-thumbnail-file thumbnail-file))))
               ("thumbnailer.py" (olb/thumbnailer file-path))))
            (t (user-error "This system platform currently not supported by org-link-beautify.\n Please contribute code to support")))))
      (when (and olb/enable-debug-p (not (file-exists-p thumbnail-file)))
        (olb/-notify-generate-thumbnail-failed comic-file thumbnail-file))
      ;; return the thumbnail file as result.
      thumbnail-file)))

(defun olb/preview-file-comic (ov path link)
  "Preview comic .cbz or .cbr file of PATH over OV overlay position for LINK element."
  (if-let* (( (display-graphic-p))
            (olb/comic-preview-command)
            (thumbnail-file (olb/-generate-preview-for-file-comic path))
            ((file-exists-p thumbnail-file))
            (image (create-image thumbnail-file nil nil :width (or olb/comic-preview-size 300))))
      (prog1 ov
        (olb/overlay-display-image ov image))
    (olb/iconify ov path link)))

;;; file: [video]

(defvar olb/video-thumbnailer-script
  (expand-file-name "scripts/thumbnailer-video.py" (file-name-directory (or load-file-name (buffer-file-name))))
  "The path of video thumbnailer script.")

(defcustom olb/video-preview-command
  (cl-case system-type
    ;; for macOS, use `qlmanage' on priority
    (darwin (or (executable-find "qlmanage") (executable-find "ffmpeg")))
    ;; for Linux, use `ffmpegthumbnailer' on priority
    (gnu/linux (or (executable-find "ffmpegthumbnailer") (executable-find "ffmpeg")))
    ;; for general, use `ffmpeg'
    ;; $ ffmpeg -i video.mp4 -ss 00:01:00.000 -vframes 1 -vcodec png -an -f rawvideo -s 119x64 out.png
    (t (or (executable-find "ffmpeg")
           olb/video-thumbnailer-script
           olb/thumbnailer-script)))
  "The available command to preview video."
  :type 'string
  :safe #'stringp
  :group 'org-link-beautify)

(defcustom olb/video-preview-list
  '("mp4" "webm" "mkv" "mov" "mpeg" "ogg" "ogv" "rmvb" "rm" "avi" "m4v" "flv")
  "A list of video file types be supported with thumbnails."
  :type 'list
  :safe #'listp
  :group 'org-link-beautify)

(defcustom olb/video-preview-size 600
  "The video thumbnail image size."
  :type 'number
  :safe #'numberp
  :group 'org-link-beautify)

(defun olb/-generate-preview-for-file-video (path)
  "Generate THUMBNAIL-FILE with THUMBNAIL-SIZE for video .mp4 etc file of PATH."
  (when (string-match "\\(.*?\\)\\(?:::\\(.*\\)\\)?\\'" path)
    (let* ((file-path (match-string 1 path))
           (search-option (match-string 2 path))
           (video-file (expand-file-name (org-link-unescape file-path)))
           (video-filename (file-name-nondirectory video-file))
           (thumbnails-dir (olb/-get-thumbnails-dir-path video-file))
           (thumbnail-file (expand-file-name (format "%s%s.png" thumbnails-dir (file-name-base video-file))))
           (thumbnail-size (or olb/video-preview-size 600))
           (proc-name (format "org-link-beautify video preview - %s" video-filename))
           (proc-buffer (format " *org-link-beautify video preview - %s*" video-filename))
           (proc (get-process proc-name)))
      (olb/-ensure-thumbnails-dir thumbnails-dir)
      (unless (file-exists-p thumbnail-file)
        ;; detect process already running?
        (unless proc
          (pcase (file-name-nondirectory olb/video-preview-command)
            ("ffmpeg"
             ;; $ ffmpeg -i video.mp4 -ss 00:00:00.001 -vframes 1 -vcodec png -an -f rawvideo -s 119x64 out.png
             (let ((thumbnail-width thumbnail-size)
                   (thumbnail-height 300))
               (start-process
                proc-name proc-buffer
                "ffmpeg"
                "-i" video-file
                "-ss" "00:00:00.001"
                "-vframes" "1"
                "-vcodec" "png"
                "-an"
                "-f" "rawvideo"
                "-s" (format "%sx%s" thumbnail-width thumbnail-height)
                thumbnail-file)))
            ("qlmanage"
             (let ((qlmanage-thumbnail-file (concat thumbnails-dir (file-name-nondirectory video-file) ".png")))
               (unless (file-exists-p qlmanage-thumbnail-file)
                 (let ((proc (start-process
                              proc-name proc-buffer
                              "qlmanage" "-x" "-t" "-s" (number-to-string thumbnail-size) video-file "-o" thumbnails-dir))
                       (proc-filter (lambda (proc output)
                                      ;; * No thumbnail created for [FILE PATH]
                                      (when (string-match "\\* No thumbnail created for.*" output)
                                        (message "[org-link-beautify] video preview FAILED on macOS QuickLook generating thumbnail for video %s" video-filename)))))
                   (set-process-filter proc proc-filter)))
               ;; then rename [file.extension.png] to [file.png]
               (when (file-exists-p qlmanage-thumbnail-file)
                 (rename-file qlmanage-thumbnail-file thumbnail-file))))
            ("ffmpegthumbnailer"
             (start-process
              proc-name proc-buffer
              "ffmpegthumbnailer" "-f" "-i" video-file "-s" (number-to-string thumbnail-size) "-o" thumbnail-file))
            ("thumbnailer-video.py"
             (make-process
              :name proc-name
              :command (list olb/video-thumbnailer-script
                             input-file
                             thumbnail-file
                             (number-to-string thumbnail-size))
              :buffer proc-buffer
              :stderr nil ; If STDERR is nil, standard error is mixed with standard output and sent to BUFFER or FILTER.
              :sentinel (lambda (proc event)
                          (when olb/enable-debug-p
                            (message (format "> proc: %s\n> event: %s" proc event)))
                          ;; (when (string= event "finished\n")
                          ;;   (kill-buffer (process-buffer proc))
                          ;;   (kill-process proc))
                          ))))))
      (when (and olb/enable-debug-p (not (file-exists-p thumbnail-file)))
        (olb/-notify-generate-thumbnail-failed video-file thumbnail-file))
      ;; return the thumbnail file as result.
      thumbnail-file)))

(defun olb/preview-file-video (ov path link)
  "Preview video file of PATH over OV overlay position for LINK element."
  (if-let* (( (display-graphic-p))
            (olb/video-preview-command)
            (thumbnail-file (olb/-generate-preview-for-file-video path))
            ((file-exists-p thumbnail-file))
            (image (create-image thumbnail-file nil nil :width 400)))
      (prog1 ov
        (olb/overlay-display-image ov image))
    (olb/iconify ov path link)))

;;; file: [audio]

(defcustom olb/audio-preview-command
  (cl-case system-type
    (darwin (or (executable-find "ffmpeg") (executable-find "qlmanage")))
    (gnu/linux (or (executable-find "ffmpeg") (executable-find "audiowaveform"))))
  "Find available audio preview command."
  :type 'string
  :safe #'stringp
  :group 'org-link-beautify)

(defcustom olb/audio-preview-list '("mp3" "wav" "flac" "ogg" "m4a" "opus" "dat")
  "A list of audio file types be supported generating audio wave form image."
  :type 'list
  :safe #'listp
  :group 'org-link-beautify)

(defcustom olb/audio-preview-size 600
  "The audio wave form image size."
  :type 'number
  :safe #'numberp
  :group 'org-link-beautify)

(defun olb/-generate-preview-for-file-audio (path)
  "Generate THUMBNAIL-FILE with THUMBNAIL-SIZE for audio .mp3 etc file of PATH."
  (when (string-match "\\(.*?\\)\\(?:::\\(.*\\)\\)?\\'" path)
    (let* ((file-path (match-string 1 path))
           (search-option (match-string 2 path))
           (audio-file (expand-file-name (org-link-unescape file-path)))
           (audio-filename (file-name-nondirectory audio-file))
           (thumbnails-dir (olb/-get-thumbnails-dir-path audio-file))
           (thumbnail-file (expand-file-name (format "%s%s.png" thumbnails-dir (file-name-base audio-file))))
           (thumbnail-size (or olb/audio-preview-size 300))
           (proc-name (format "org-link-beautify audio preview - %s" audio-filename))
           (proc-buffer (format " *org-link-beautify audio preview - %s*" audio-filename))
           (proc (get-process proc-name)))
      (olb/-ensure-thumbnails-dir thumbnails-dir)
      (unless (file-exists-p thumbnail-file)
        (unless proc
          (pcase (file-name-nondirectory olb/audio-preview-command)
            ("ffmpeg"
             (start-process
              proc-name proc-buffer
              "ffmpeg" "-i" audio-file
              "-filter_complex" "[0:a]aformat=channel_layouts=mono,compand=gain=-6,showwavespic=s=600x120:colors=#9cf42f[fg];color=s=600x120:color=#44582c,drawgrid=width=iw/10:height=ih/5:color=#9cf42f@0.1[bg];[bg][fg]overlay=format=auto,drawbox=x=(iw-w)/2:y=(ih-h)/2:w=iw:h=1:color=#9cf42f"
              "-frames:v" "1"
              thumbnail-file))
            ("qlmanage"
             (let ((qlmanage-thumbnail-file (concat thumbnails-dir (file-name-nondirectory audio-file) ".png")))
               (unless (file-exists-p qlmanage-thumbnail-file)
                 (start-process
                  proc-name proc-buffer
                  "qlmanage" "-x" "-t" "-s" (number-to-string thumbnail-size) audio-file "-o" thumbnails-dir))
               ;; then rename [file.extension.png] to [file.png]
               (when (file-exists-p qlmanage-thumbnail-file)
                 (rename-file qlmanage-thumbnail-file thumbnail-file))))
            ("audiowaveform"
             (start-process
              proc-name proc-buffer
              "audiowaveform" "-i" audio-file "-o" thumbnail-file)))))
      (when (and olb/enable-debug-p (not (file-exists-p thumbnail-file)))
        (olb/-notify-generate-thumbnail-failed audio-file thumbnail-file))
      ;; return the thumbnail file as result.
      thumbnail-file)))

(defun olb/preview-file-audio (ov path link)
  "Preview audio file of PATH over OV overlay position for LINK element."
  (if-let* (( (display-graphic-p))
            (olb/audio-preview-command)
            (thumbnail-file (olb/-generate-preview-for-file-audio path))
            ((file-exists-p thumbnail-file))
            (image (create-image thumbnail-file nil nil :width (or olb/audio-preview-size 300))))
      (prog1 ov
        (olb/overlay-display-image ov image))
    (olb/iconify ov path link)))

;;; file: [subtitle]

(defcustom olb/subtitle-preview-command olb/thumbnailer-script
  "The command to preview subtitle file."
  :type 'string
  :safe #'stringp
  :group 'org-link-beautify)

;; https://en.wikipedia.org/wiki/Subtitles
(defcustom olb/subtitle-preview-list
  '("ass" "srt" "sub" "vtt" "ssf")
  "A list of subtitle file types support previewing."
  :type 'list
  :safe #'listp
  :group 'org-link-beautify)

(defcustom olb/subtitle-preview-size 300
  "The subtitle preview image size."
  :type 'number
  :safe #'numberp
  :group 'org-link-beautify)

(defun olb/-generate-preview-for-file-subtitle (path)
  "Generate THUMBNAIL-FILE with THUMBNAIL-SIZE for subtitle file of PATH."
  (when (string-match "\\(.*?\\)\\(?:::\\(.*\\)\\)?\\'" path)
    (let* ((file-path (match-string 1 path))
           (search-option (match-string 2 path))
           (subtitle-file (expand-file-name (org-link-unescape file-path))))
      (if-let* ((olb/subtitle-preview-command)
                (thumbnails-dir (olb/-get-thumbnails-dir-path subtitle-file))
                (thumbnail-file (expand-file-name (format "%s%s.png" thumbnails-dir (file-name-base subtitle-file))))
                (thumbnail-size (or olb/subtitle-preview-size 200))
                (proc-name (format "org-link-beautify subtitle preview - %s" subtitle-file))
                (proc-buffer (format " *org-link-beautify subtile preview - %s*" subtitle-file))
                (proc (get-process proc-name)))
          (prog1 thumbnail-file ; return the thumbnail file as result.
            (unless (file-exists-p thumbnail-file)
              (olb/-ensure-thumbnails-dir thumbnails-dir)
              (pcase (file-name-nondirectory olb/subtitle-preview-command)
                ("thumbnailer.py" (olb/thumbnailer file-path)))))
        (let* ((subtitle-file-context (split-string (shell-command-to-string (format "head -n 20 '%s'" subtitle-file)) "\n"))
               (text (concat "\n" (olb/-display-content-block subtitle-file-context))))
          ;; return the subtitle file context as result.
          text)))))

(defun olb/preview-file-subtitle (ov path link)
  "Preview subtitle file of PATH over OV overlay position for LINK element."
  (if-let* (( (display-graphic-p))
            (olb/subtitle-preview-command)
            (thumbnail-file (olb/-generate-preview-for-file-subtitle path))
            ((file-exists-p thumbnail-file))
            (image (create-image thumbnail-file nil nil :width (or olb/subtitle-preview-size 300))))
      (prog1 ov
        (olb/overlay-display-image ov image))
    (if-let* ((text (olb/-generate-preview-for-file-subtitle path)))
        (prog1 ov
          (overlay-put ov 'after-string text)
	      (overlay-put ov 'face         'default))
      (olb/iconify ov path link))))

;;; file: [archive file]

(defcustom olb/archive-preview-list
  '("zip" "rar" "7z" "gz" "tar" "tar.gz" "tar.bz2" "xz" "zst")
  "A list of archive file types support previewing."
  :type 'list
  :safe #'listp
  :group 'org-link-beautify)

(defcustom olb/archive-preview-command-alist
  '(("zip" . "unzip -l")
    ("rar" . "unrar l")
    ("7z" . "7z l -ba") ; -ba - suppress headers; undocumented.
    ("gz" . "gzip --list")
    ;; ("bz2" . "")
    ("tar" . "tar --list")
    ("tar.gz" . "tar --gzip --list")
    ("tar.bz2" . "tar --bzip2 --list")
    ("xz" . "xz --list")
    ("zst" . "zstd --list"))
  "An alist of archive types supported archive preview inside files list.
Each element has form (ARCHIVE-FILE-EXTENSION COMMAND)."
  :type '(alist :value-type (group string))
  :group 'org-link-beautify)

(defun olb/-generate-preview-for-file-archive (path)
  "Get the files list preview of archive file at PATH."
  (when (string-match "\\(.*?\\)\\(?:::\\(.*\\)\\)?\\'" path)
    (let* ((file-path (match-string 1 path))
           (search-option (match-string 2 path))
           (archive-file (expand-file-name (org-link-unescape file-path)))
           (archive-extension (file-name-extension archive-file))
           (command (cdr (assoc archive-extension olb/archive-preview-command-alist)))
           (execute-command (format "%s '%s'" command archive-file))
           (archive-files-list (split-string (shell-command-to-string execute-command) "\n"))
           (text (concat "\n" (olb/-display-content-block archive-files-list))))
      ;; return the files list in archive file as result.
      text)))

(defun olb/preview-file-archive (ov path link)
  "Preview archive file link of PATH over OV overlay position for LINK element."
  (if-let* ((text (olb/-generate-preview-for-file-archive path)))
      (prog1 ov
        (overlay-put ov 'after-string text)
	    (overlay-put ov 'face         'default)
	    (overlay-put ov 'keymap       olb/keymap))
    (olb/iconify ov path link)))

;;; pdf: & docview: link type

(defun olb/preview-pdf (ov path link)
  "Preview pdf: link of PATH over OV overlay position for LINK element."
  (if-let* (( (display-graphic-p))
            (thumbnail-file (olb/-generate-preview-for-file-pdf path))
            ((file-exists-p thumbnail-file))
            ;; reference `org--create-inline-image'
            (width (org-display-inline-image--width link))
            (image (org--create-inline-image thumbnail-file width)))
      (prog1 ov
        (olb/overlay-display-image ov image))
    (olb/iconify ov path link)))

;;; epub: link type

(defalias 'olb/preview-epub 'olb/preview-file-epub
  "Preview epub: link of PATH over OV overlay position for LINK element.")

;;; nov: link type

(defalias 'olb/preview-nov 'olb/preview-epub
  "Preview nov: link of PATH over OV overlay position for LINK element.")

;;; video: link type

(defalias 'olb/preview-video 'olb/preview-file-video
  "Preview video: link of PATH over OV overlay position for LINK element.")

;;; audio: link type

(defalias 'olb/preview-audio 'olb/preview-file-audio
  "Preview audio: link of PATH over OV overlay position for LINK element.")

;;; org-contact: link type

(defun olb/-generate-preview-for-org-contacts (name)
  "Get the avatar of org-contact in NAME."
  (let* ((epom (org-contacts-search-contact name)))
    (org-contacts-get-avatar-icon epom)))

;;; TEST:
;; (olb/-generate-preview-for-org-contacts "stardiviner")

(defun olb/preview-org-contact (ov path link)
  "Preview org-contct: link of PATH over OV overlay position for LINK element."
  (if-let* ((name path)
            ( (display-graphic-p))
            (image (olb/-generate-preview-for-org-contacts name)))
      (prog1 ov
        (overlay-put ov 'display image)
        (overlay-put ov 'after-string (concat
                                       (propertize "{" 'face '(:foreground "purple2"))
                                       (propertize name 'face 'org-verbatim)
                                       (propertize "}" 'face '(:foreground "purple2")))))
    (if-let* ((text (org-element-property :title (org-contacts-search-contact name))))
        (overlay-put ov 'after-string (concat
                                       (propertize "{" 'face '(:foreground "purple2"))
                                       (propertize text 'face 'org-verbatim)
                                       (propertize "}" 'face '(:foreground "purple2"))))
      (olb/iconify ov path link))))

;;; org-bookmark: link type

(require 'org-bookmarks nil t)

(defun olb/-generate-preview-for-org-bookmarks (path)
  "Get the bookmark content at title PATH."
  (when (string-match "\\(.*?\\)\\(?:::\\(.*\\)\\)?\\'" path)
    (let* ((bookmark-title (match-string 1 path))
           (search-option (match-string 2 path))
           ;; reference `org-bookmarks-link-open'
           (bookmark-content (org-bookmarks--get-bookmark-content path))
           (cwd (file-name-directory org-bookmarks-file))
           (text (concat "\n" (olb/-display-org-content bookmark-content))))
      ;; return the files list in archive file as result.
      text)))

(defun olb/preview-org-bookmark (ov path link)
  "Preview org-bookmark: link of PATH over OV overlay position for LINK element."
  (if-let* (((require 'org-bookmarks nil t))
            (text (olb/-generate-preview-for-org-bookmarks path)))
      (prog1 ov
        (overlay-put ov 'after-string text)
        (overlay-put ov 'face         'org-link))
    (olb/iconify ov path link)))

;;; excalidraw: link type

(defun olb/preview-excalidraw (ov path link)
  "Preview excalidraw file of PATH over OV overlay position for LINK element."
  ;; TODO: reference `org-excalidraw--shell-cmd-to-svg'
  nil)

;;; geo: link type

(defun olb/preview-geography (ov path link)
  "Preview geo: link of PATH over OV overlay position for LINK element."
  ;; TODO
  nil)

;;; git: link type

(defcustom olb/git-preview nil
  "Whether enable git: link type preview."
  :type 'boolean
  :safe #'booleanp
  :group 'org-link-beautify)

(defun olb/-generate-preview-for-git (ov path link)
  "Get the content on OV overlay of PATH at LINK element."
  (when (string-match "\\(.*?\\)\\(?:::\\(.*\\)\\)?\\'" path)
    (let* ((file-path (match-string 1 path))
           (commit (match-string 2 path))
           ;; TODO: use `vc-git-*' or `magit' API to get git commit blob content.
           (commit-diff (vc-git-symbolic-commit commit))
           (text (concat "\n" (olb/-display-content-block commit-diff))))
      text)))

(defun olb/preview-git (ov path link)
  "Preview git: link of PATH over OV overlay position for LINK element."
  (if olb/git-preview
      (when-let* ((text (olb/-generate-preview-for-git ov path link)))
        (overlay-put ov 'after-string text)
        (overlay-put ov 'face 'org-block))
    (olb/iconify ov path link)))

;;; http[s]: url link type

(defcustom olb/url-preview-command
  (cl-case system-type
    (darwin
     (cond
      ;; Google Chrome headless screenshot
      ((file-exists-p "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
       "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
      ;; webkit2png
      ((executable-find "webkit2png") "webkit2png")
      ;; monolith
      ((executable-find "monolith") "monolith")))
    (gnu/linux
     (cond
      ;; Google Chrome headless screenshot
      ((executable-find "chrome") (executable-find "google-chrome"))
      ;; webkit2png
      ((executable-find "webkit2png") "webkit2png")
      ;; monolith
      ((executable-find "monolith") "monolith"))))
  "Find available URL web page screenshot archive command."
  :type 'string
  :safe #'stringp
  :group 'org-link-beautify)

(defcustom olb/url-preview-size 800
  "The url web page thumbnail image size."
  :type 'number
  :safe #'numberp
  :group 'org-link-beautify)

(defun olb/-generate-preview-for-url (ov path link)
  "Generate screenshot archive for the URL PATH web page on OV overlay at LINK element."
  (let* ((type (org-element-property :type link))
         (url (concat type ":" path))
         (thumbnails-dir (olb/-get-thumbnails-dir-path (buffer-file-name)))
         (thumbnail-filename (format "org-link-beautify screenshot of sha1 URL %s.png" (sha1 url)))
         (thumbnail-file (expand-file-name thumbnail-filename thumbnails-dir))
         (html-archive-file (concat (file-name-sans-extension thumbnail-file) ".html"))
         (thumbnail-size (or olb/url-preview-size 1000))
         (proc-name (format "org-link-beautify url screenshot - %s" url))
         (proc-buffer (format " *org-link-beautify url screenshot - %s*" url))
         (proc (get-process proc-name)))
    (olb/-ensure-thumbnails-dir thumbnails-dir)
    (unless (or (file-exists-p thumbnail-file)
                (file-exists-p html-archive-file))
      (when olb/url-preview-command
        (unless proc
          (pcase olb/url-preview-command
            ((or "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" "google-chrome")
             ;; $ google-chrome --headless --screenshot=screenshot.png "https://www.chromestatus.com/"
             (start-process
              proc-name proc-buffer
              olb/url-preview-command
              "--headless"
              (format "--screenshot=%s" thumbnail-file)
              url))
            ("webkit2png"
             (make-process
              :name proc-name
              :command (list "webkit2png" url "-o" thumbnail-file)
              :buffer proc-buffer
              :stderr nil ; If STDERR is nil, standard error is mixed with standard output and sent to BUFFER or FILTER.
              :sentinel (lambda (proc event)
                          (when (string= event "finished\n")
                            (kill-buffer (process-buffer proc))
                            (kill-process proc)))))
            ("monolith"
             (let* ((html-archive-file (concat (file-name-sans-extension thumbnail-file) ".html")))
               (make-process
                :name proc-name
                :command (list "monolith" "--no-audio" "--no-video" url "--output" html-archive-file)
                :buffer proc-buffer
                :stderr nil ; If STDERR is nil, standard error is mixed with standard output and sent to BUFFER or FILTER.
                :sentinel (lambda (proc event)
                            (when (string= event "finished\n")
                              (kill-buffer (process-buffer proc))
                              (kill-process proc))))))))))
    (when (and olb/enable-debug-p (not (file-exists-p thumbnail-file)))
      (olb/-notify-generate-thumbnail-failed url thumbnail-file))))

(defun olb/preview-url (ov path link)
  "Preview http[s]: URL link of PATH over OV overlay position for LINK element."
  (if-let* (( (display-graphic-p))
            (olb/url-preview-command)
            (thumbnail-file (olb/-generate-preview-for-url ov path link))
            ((file-exists-p thumbnail-file))
            (image (create-image thumbnail-file nil nil :width (or olb/url-preview-size 600))))
      (prog1 ov
        (olb/overlay-display-image ov image))
    (olb/iconify ov path link)))

;;; Insert Org link without description based on smart detecting file extension.

(defun olb/remove-description (orig-func link-raw &optional link-description)
  "Advice function to remove LINK-DESCRIPTION from LINK-RAW around ORIG-FUNC.

This is for link image previewing to get around function `org-link-preview'
\(original named `org-toggle-inline-images'\) parameter `include-linked'."
  (let ((link-type (when (string-match org-link-types-re link-raw) (match-string 1 link-raw)))
        (extension (file-name-extension link-raw)))
    (when (or (member extension image-file-name-extensions) ; image files
              (member extension '("pdf" "epub" "mobi" "azw3" "lit" "fb2" "fb2.zip")) ; ebook files
              (member extension '("avi" "rmvb" "ogg" "ogv" "mp4" "mkv" "mov" "mpeg" "webm" "flv" "ts" "mpg")) ; video files
              (member extension '("mp3" "wav" "flac" "ogg" "m4a" "opus" "dat")) ; audio files
              (member extension '("cbr" "cbz" "cb7" "cba" "cbt")) ; comic files
              (member extension '("zip" "rar" "7z" "gz" "tar" "tar.gz" "tar.bz2" "xz" "zst")) ; archive files
              (member extension '("ass" "srt" "sub" "vtt" "ssf")) ; subtitle files
              (member link-type '("info" "help" "shortdoc" "man" "woman" "id" "custom-id" "coderef"))
              (member link-type '("elisp" "shell" "js" "javascript" "grep" "occur" "git"))
              (member link-type '("mailto" "rss" "news" "wikipedia" "irc" "magnet" "wechat" "web-browser" "eww" "chrome" "edge"))
              (member link-type '("org-ql-search" "org-contact" "org-bookmark" "orgit" "orgit-rev" "orgit-log"))
              ;; Emacs package special link types
              ;; NOTE: "epub" "nov" page-number thumbnail generating not supported.
              (member link-type '("pdf" "pdfview" "docview")) ; "epub" "nov"
              (member link-type '("video" "videocite" "audio" "audiocite" "excalidraw"))
              ;; speail meaning link types
              (member link-type '("geo"))
              ;; special application link types
              (member link-type '("vscode" "macappstore")))
      (setq link-description nil)))
  (funcall orig-func link-raw link-description))


;;; minor mode `org-link-beautify-mode'

;;;###autoload
(defun olb/enable ()
  "Enable `org-link-beautify'."
  (dolist (link-type (mapcar #'car org-link-parameters))
    (pcase link-type
      ("file" (org-link-set-parameters link-type :preview #'olb/preview-file)) ; `org-link-preview-file',
      ("attachment" (org-link-set-parameters link-type :preview #'olb/preview-attachment)) ; `org-attach-preview-file'
      ("docview" (org-link-set-parameters link-type :preview #'olb/preview-pdf)) ; extension `doc-view'
      ("pdfview" (org-link-set-parameters link-type :preview #'olb/preview-pdf)) ; extension `pdf-tools'
      ("pdf" (org-link-set-parameters link-type :preview #'olb/preview-pdf))
      ("epub" (org-link-set-parameters link-type :preview #'olb/preview-epub))
      ("nov" (org-link-set-parameters link-type :preview #'olb/preview-nov)) ; extension `nov'
      ("geo" (org-link-set-parameters link-type :preview #'olb/preview-geography))
      ("http" (org-link-set-parameters link-type :preview #'olb/iconify))
      ("https" (org-link-set-parameters link-type :preview #'olb/iconify))
      ("ftp" (org-link-set-parameters link-type :preview #'olb/iconify))

      ;; Org mode internal link types
      ("custom-id" (org-link-set-parameters link-type :preview #'olb/iconify))
      ("id" (org-link-set-parameters link-type :preview #'olb/iconify))
      ("coderef" (org-link-set-parameters link-type :preview #'olb/iconify))
      ("elisp" (org-link-set-parameters link-type :preview #'olb/iconify))
      ("eshell" (org-link-set-parameters link-type :preview #'olb/iconify))
      ("shell" (org-link-set-parameters link-type :preview #'olb/iconify))
      ("man" (org-link-set-parameters link-type :preview #'olb/iconify))
      ("woman" (org-link-set-parameters link-type :preview #'olb/iconify))
      ("info" (org-link-set-parameters link-type :preview #'olb/iconify))
      ("help" (org-link-set-parameters link-type :preview #'olb/iconify))
      ("shortdoc" (org-link-set-parameters link-type :preview #'olb/iconify))
      
      ;; Org mode external link types
      ("grep" (org-link-set-parameters link-type :preview #'olb/iconify))
      ("occur" (org-link-set-parameters link-type :preview #'olb/iconify))
      ("mailto" (org-link-set-parameters link-type :preview #'olb/iconify))
      ("news" (org-link-set-parameters link-type :preview #'olb/iconify))
      ("rss" (org-link-set-parameters link-type :preview #'olb/iconify))
      ("elfeed" (org-link-set-parameters link-type :preview #'olb/iconify)) ; extension `elfeed'
      ("wikipedia" (org-link-set-parameters link-type :preview #'olb/iconify))
      ("irc" (org-link-set-parameters link-type :preview #'olb/iconify))
      ("wechat" (org-link-set-parameters link-type :preview #'olb/iconify))
      ("magnet" (org-link-set-parameters link-type :preview #'olb/iconify))
      ;; ("git" (org-link-set-parameters link-type :preview #'olb/preview-git))
      ("eww" (org-link-set-parameters link-type :preview #'olb/iconify)) ; EWW
      ("chrome" (org-link-set-parameters link-type :preview #'olb/iconify))
      ("edge" (org-link-set-parameters link-type :preview #'olb/iconify))
      ("mu4e" (org-link-set-parameters link-type :preview #'olb/iconify))
      ;; ("web-browser" (org-link-set-parameters link-type :preview #'olb/preview-browser))
      
      ;; org-ref link types
      ("cite" (org-link-set-parameters link-type :preview #'olb/iconify))
      ("ref" (org-link-set-parameters link-type :preview #'olb/iconify))
      ("doi" (org-link-set-parameters link-type :preview #'olb/iconify))
      ("bibtex" (org-link-set-parameters link-type :preview #'olb/iconify))
      ("bibliography" (org-link-set-parameters link-type :preview #'olb/iconify))
      
      ;; org-mode extensions link types
      ("org-ql-search" (org-link-set-parameters link-type :preview #'olb/iconify)) ; extension `org-ql'
      ("org-contact" (org-link-set-parameters link-type :preview #'olb/preview-org-contact)) ; extension `org-contacts'
      ("org-bookmark" (org-link-set-parameters link-type :preview #'olb/preview-org-bookmark)) ; extension `org-bookmarks'
      ;; ("orgit-rev" (org-link-set-parameters link-type :preview #'olb/preview-git)) ; extension `orgit'
      ;; ("orgit-log" (org-link-set-parameters link-type :preview #'olb/preview-git)) ; extension `orgit'
      ;; ("orgit" (org-link-set-parameters link-type :preview #'olb/preview-git))     ; extension `orgit'
      ("excalidraw" (org-link-set-parameters link-type :preview #'olb/preview-excalidraw)) ; extension `org-excalidraw'
      
      ;; org-media-note link types
      ("video" (org-link-set-parameters link-type :preview #'olb/preview-video)) ; `org-media-note'
      ("audio" (org-link-set-parameters link-type :preview #'olb/preview-audio)) ; `org-media-note'
      ("videocite" (org-link-set-parameters link-type :preview #'olb/preview-video)) ; `org-media-note'
      ("audiocite" (org-link-set-parameters link-type :preview #'olb/preview-audio)) ; `org-media-note'
      
      ;; other link types
      ("eaf" (org-link-set-parameters link-type :preview #'olb/iconify)) ; extension `emacs-application-framework'
      ("javascript" (org-link-set-parameters link-type :preview #'olb/iconify)) ; Org mode inline source code link
      ("js" (org-link-set-parameters link-type :preview #'olb/iconify)) ; Org mode inline source code link
      ("vscode" (org-link-set-parameters link-type :preview #'olb/iconify)) ; Visual Studio Code
      ("macappstore" (org-link-set-parameters link-type :preview #'olb/iconify)) ; Mac App Store
      ("fuzzy" (org-link-set-parameters link-type :preview #'olb/iconify)) ; org-mode internal raw link type
      (_ (org-link-set-parameters link-type :preview #'olb/iconify))))
  ;; remove link description
  (advice-add 'org-link-make-string :around #'olb/remove-description))

;;;###autoload
(defun olb/disable ()
  "Disable `org-link-beautify'."
  (dolist (link-type (mapcar #'car org-link-parameters))
    (pcase link-type
      ("file" (org-link-set-parameters "file" :preview #'org-link-preview-file))
      ("attachment" (org-link-set-parameters "attachment" :preview #'org-attach-preview-file))
      (_ (org-link-set-parameters link-type :preview nil))))
  (advice-remove 'org-link-make-string #'olb/remove-description))

(defvar olb/mode-map
  (let ((map (make-sparse-keymap)))
    map)
  "The `org-link-beautify-mode' minor mode map.")

;;;###autoload
(define-minor-mode org-link-beautify-mode
  "A minor mode to beautify Org Mode links with icons, and inline preview etc."
  :group 'org-link-beautify
  :global t
  :init-value nil
  :lighter " ߷"
  :keymap olb/mode-map ; avoid to enable `olb/keymap' globally everywhere.
  (if org-link-beautify-mode
      (olb/enable)
    (olb/disable)))



(provide 'org-link-beautify-new)

;;; org-link-beautify-new.el ends here

;; Local Variables:
;; read-symbol-shorthands: (("olb/" . "org-link-beautify-") (":olb/" . ":org-link-beautify-"))
;; package-lint--sane-prefixes: "^olb/"
;; End:
