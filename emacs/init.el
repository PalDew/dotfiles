;; Make gc pauses faster by decreasing the threshold.
(setq gc-cons-threshold (* 2 1000 1000))
;; Increase the amount of data which Emacs reads from the process
(setq read-process-output-max (* 1024 1024)) ;; 1mb
(put 'scroll-left 'disabled nil)

(use-package emacs
  :custom
  (menu-bar-mode nil)         ;; Disable the menu bar
  (scroll-bar-mode nil)       ;; Disable the scroll bar
  (tool-bar-mode nil)         ;; Disable the tool bar
  (inhibit-startup-screen t)  ;; Disable welcome screen
  (delete-selection-mode t)   ;; Select text and delete it by typing.
  (electric-indent-mode nil)  ;; Turn off the weird indenting that Emacs does by default.
  (electric-pair-mode t)      ;; Turns on automatic parens pairing
  (blink-cursor-mode nil)     ;; Don't blink cursor
  (global-auto-revert-mode t) ;; Automatically reload file and show changes if the file has changed
  (dired-kill-when-opening-new-dired-buffer t) ;; Dired don't create new buffer
  (recentf-mode t) ;; Enable recent file mode
  (global-visual-line-mode t)           ;; Enable truncated lines
  (display-line-numbers-type 'relative) ;; Relative line numbers
  (global-display-line-numbers-mode t)  ;; Display line numbers
  (mouse-wheel-progressive-speed nil) ;; Disable progressive speed when scrolling
  (scroll-conservatively 10) ;; Smooth scrolling
  (tab-width 2)
  (make-backup-files nil) ;; Stop creating ~ backup files
  (auto-save-default nil) ;; Stop creating # auto save files
  :hook
  (prog-mode . (lambda () (hs-minor-mode t))) ;; Enable folding hide/show globally
  :config
  ;; Move customization variables to a separate file and load it, avoid filling up init.el with unnecessary variables
  (setq custom-file (locate-user-emacs-file "custom-vars.el"))
  (load custom-file 'noerror 'nomessage)
  :bind (
  ("C-=" . text-scale-increase)
  ("C--" . text-scale-decrease)
  ("<C-wheel-up>" . text-scale-increase)
  ("<C-wheel-down>" . text-scale-decrease)
         ([escape] . keyboard-escape-quit) ;; Makes Escape quit prompts (Minibuffer Escape)
         ))


;;setting up package urls
(require 'use-package-ensure) ;; Load use-package-always-ensure
(setq use-package-always-ensure t) ;; Always ensures that a package is installed
(setq package-archives '(("melpa" . "https://melpa.org/packages/") ;; Sets default package repositories
                         ("org" . "https://orgmode.org/elpa/")
                         ("elpa" . "https://elpa.gnu.org/packages/")
                         ("nongnu" . "https://elpa.nongnu.org/nongnu/"))) ;; For Eat Terminal

;;
(use-package gruvbox-theme
  :config
  (load-theme 'gruvbox-dark-medium t)) ;; We need to add t to trust this package
(add-to-list 'default-frame-alist '(alpha-background )) ;; For all new frames henceforth
(set-face-attribute 'default nil
                    :font "Iosevka Nerd Font" ;; Set your favorite type of font or download JetBrains Mono
                    :height 90
                    :weight 'semi-bold)
(setq-default line-spacing 0.12)

;; A better modeline than the stardard one
(use-package doom-modeline
  :init (doom-modeline-mode 1)
  :custom
  (doom-modeline-height 25)     ;; Sets modeline height
  (doom-modeline-bar-width 5)   ;; Sets right bar width
  (doom-modeline-persp-name t)  ;; Adds perspective name to modeline
  (doom-modeline-persp-icon t)) ;; Adds folder icon next to persp name
(use-package diminish) ;; make doomline more minimal
;;RGB brackets;
(use-package rainbow-delimiters
  :ensure t
  :config
  (rainbow-delimiters-mode 1))

(use-package eat
  :hook ('eshell-load-hook #'eat-eshell-mode))

;; Cuz I am a Python bro!!
(use-package lsp-pyright
  :ensure t
  :custom (lsp-pyright-langserver-command "pyright") ;; or basedpyright
  :hook (python-mode . (lambda ()
                          (require 'lsp-pyright)
                          (lsp))))  ; or lsp-deferred

;; Just org-mode things
(use-package org
  :ensure nil
  :custom
 (org-todo-keywords
      '((sequence "Task(t)" "Idea(i)" "Insight(e)" "Blog(b!)" "Started(s!)" "|" "Paused(p!)" "Abandoned(a!)" "Done(d!)")))
 (org-log-done 'time)       ;; Log timestamp when marking tasks as done
  (org-log-into-drawer t)    ;; Store logs inside a :LOGBOOK: drawer
  (org-edit-src-content-indentation 4) ;; Set src block automatic indent to 4 instead of 2.
  (org-agenda-files (directory-files "/home/palash/Documents/scratch/Emacs Diary/" "\\.org\\z"))
  :hook
  (org-mode . org-indent-mode) ;; Indent text
  ;; The following prevents <> from auto-pairing when electric-pair-mode is on.
  ;; Otherwise, org-tempo is broken when you try to <s TAB...
  (org-mode . (lambda ()
                (setq-local electric-pair-inhibit-predicate
                            `(lambda (c)
                               (if (char-equal c ?<) t (,electric-pair-inhibit-predicate c))))))
  )
;; Generate a table of contents for org files, when invoked
(use-package toc-org
  :commands toc-org-enable
  :hook (org-mode . toc-org-mode))
;; Make org headings pretty
(use-package org-superstar
  :after org
  :hook (org-mode . org-superstar-mode))
;; To insert quicker code blocks in literate programming
(use-package org-tempo
  :ensure nil
  :after org)

;; auto-completion in buffer
;; when run alone, it just gives better nagivational skills in find files and dired
;; apparently it is the one giving suggestions for completions
(use-package corfu
  ;; Optional customizations
  :custom
  (corfu-cycle t)                ;; Enable cycling for `corfu-next/previous'
  (corfu-auto t)                 ;; Enable auto completion
  (corfu-auto-prefix 2)          ;; Minimum length of prefix for auto completion.
  (corfu-popupinfo-mode t)       ;; Enable popup information
  (corfu-popupinfo-delay 0.5)    ;; Lower popupinfo delay to 0.5 seconds from 2 seconds
  (corfu-separator ?\s)          ;; Orderless field separator, Use M-SPC to enter separator
  ;; (corfu-quit-at-boundary nil)   ;; Never quit at completion boundary
  ;; (corfu-quit-no-match nil)      ;; Never quit, even if there is no match
  ;; (corfu-preview-current nil)    ;; Disable current candidate preview
  ;; (corfu-preselect 'prompt)      ;; Preselect the prompt
  ;; (corfu-on-exact-match nil)     ;; Configure handling of exact matches
  ;; (corfu-scroll-margin 5)        ;; Use scroll margin
  (completion-ignore-case t)
  ;; Enable indentation+completion using the TAB key.
  ;; `completion-at-point' is often bound to M-TAB.
  (tab-always-indent 'complete)
  (corfu-preview-current nil) ;; Don't insert completion without confirmation
  ;; Recommended: Enable Corfu globally.  This is recommended since Dabbrev can
  ;; be used globally (M-/).  See also the customization variable
  ;; `global-corfu-modes' to exclude certain modes.
  :init
  (global-corfu-mode))

;; More auto-completions at the the point of cursor
(use-package cape
  :after corfu
  :init
  ;; Add to the global default value of `completion-at-point-functions' which is
  ;; used by `completion-at-point'.  The order of the functions matters, the
  ;; first function returning a result wins.  Note that the list of buffer-local
  ;; completion functions takes precedence over the global list.
  ;; The functions that are added later will be the first in the list

  (add-to-list 'completion-at-point-functions #'cape-dabbrev) ;; Complete word from current buffers
  (add-to-list 'completion-at-point-functions #'cape-dict) ;; Dictionary completion
  (add-to-list 'completion-at-point-functions #'cape-file) ;; Path completion
  (add-to-list 'completion-at-point-functions #'cape-elisp-block) ;; Complete elisp in Org or Markdown mode
  (add-to-list 'completion-at-point-functions #'cape-keyword) ;; Keyword/Snipet completion
  ;;(add-to-list 'completion-at-point-functions #'cape-abbrev) ;; Complete abbreviation
  ;;(add-to-list 'completion-at-point-functions #'cape-history) ;; Complete from Eshell, Comint or minibuffer history
  ;;(add-to-list 'completion-at-point-functions #'cape-line) ;; Complete entire line from current buffer
  ;;(add-to-list 'completion-at-point-functions #'cape-elisp-symbol) ;; Complete Elisp symbol
  ;;(add-to-list 'completion-at-point-functions #'cape-tex) ;; Complete Unicode char from TeX command, e.g. \hbar
  ;;(add-to-list 'completion-at-point-functions #'cape-sgml) ;; Complete Unicode char from SGML entity, e.g., &alpha
  ;;(add-to-list 'completion-at-point-functions #'cape-rfc1345) ;; Complete Unicode char using RFC 1345 mnemonics
  )

;; Vertical list of things in the <M-> and <C-> buffers
(use-package vertico
  :init
  (vertico-mode))

;; fuzzy completion engine 
(use-package orderless
  :custom
  (completion-styles '(orderless basic))
  (completion-category-overrides '((file (styles basic partial-completion)))))

;; small description for vertico suggestions
(use-package marginalia
  :after vertico
  :init
  (marginalia-mode))

(use-package projectile
  :init
  (projectile-mode)
  :custom
  (projectile-run-use-comint-mode t) ;; Interactive run dialog for running projects
  (projectile-switch-project-action #'projectile-dired) ;; Open dired when switching projects
  (projectile-project-search-path '("/home/Palash/Documents/scratch/"
                                    "/home/Palash/Documents/Experiment1/"
                                    "/home/Palash/Documents/Obsidian-new/")))
(use-package yasnippet-snippets
  :hook (prog-mode . yas-minor-mode))

;; magit - best git integration tool in emacs. 
(use-package magit
  :commands magit-status)

(use-package diff-hl
  :hook ((dired-mode         . diff-hl-dired-mode-unless-remote)
         (magit-pre-refresh  . diff-hl-magit-pre-refresh)
         (magit-post-refresh . diff-hl-magit-post-refresh))
  :init (global-diff-hl-mode))

(use-package consult
  :ensure t
  :hook (completion-list-mode . consult-preview-at-point-mode)
  :init
  ;; Configure register preview
  (setq register-preview-delay 0.5
        register-preview-function #'consult-register-format)
  (advice-add #'register-preview :override #'consult-register-window)

  ;; Use Consult for xref and definitions
  (setq xref-show-xrefs-function #'consult-xref
        xref-show-definitions-function #'consult-xref)

  ;; Use Consult for imenu
  (setq imenu-default-menubar-key nil
        imenu-case-fold-search nil
        imenu-use-markers nil
        imenu-sort-function #'imenu--sort-alphabetically
        imenu-list-function #'consult-imenu)
  :config
  ;; Configure preview (optional, but recommended)
  (setq consult-preview-key '(:debounce 0.1 any)) ;; Preview on any keypress with slight debounce

  ;; Configure sorting (optional)
  ;; (setq consult-buffer-sort-predicate 'visibility-then-lru) ;; Sort buffers by visibility and last recently used

  ;; Projectile integration (adjust if you have a different project function)
  (when (featurep 'projectile)
    (autoload 'projectile-project-root "projectile")
    (setq consult-project-function (lambda (_) (projectile-project-root))))

  ;; Orderless integration (if you use Orderless for fuzzy matching)
  (when (featurep 'orderless)
    (setq completion-styles '(orderless basic)
          completion-category-defaults nil
          completion-category-overrides '((file (styles basic partial-completion)))))

  ;; Embark integration (for actions on candidates)
  (when (featurep 'embark)
    (require 'embark)
    (setq consult-completion-in-comint-mode t ;; Enable Consult completion in Comint mode
          embark-completing-read-handlers
          (append '((t . embark-act)) embark-completing-read-handlers)))

  ;; Marginalia integration (for displaying documentation)
  (when (featurep 'marginalia)
    (require 'marginalia)
    (marginalia-mode 1)
    (setq consult-preview-annotate 'marginalia))
  )

;; for reading and annotating  pdf-files 
(use-package pdf-tools
  :ensure t
  :config
  (pdf-tools-install))

;;epub files
(use-package nov
  :ensure t
  :init
  (add-to-list 'auto-mode-alist '("\\.epub\\'" . nov-mode)))
