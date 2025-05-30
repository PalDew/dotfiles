;;; emacsql-sqlite.el --- Code used by both SQLite back-ends  -*- lexical-binding:t -*-

;; This is free and unencumbered software released into the public domain.

;; Author: Jonas Bernoulli <emacs.emacsql@jonas.bernoulli.dev>
;; Maintainer: Jonas Bernoulli <emacs.emacsql@jonas.bernoulli.dev>

;; SPDX-License-Identifier: Unlicense

;;; Commentary:

;; This library contains code that is used by both SQLite back-ends.

;;; Code:

(require 'emacsql)

;;; Base class

(defclass emacsql--sqlite-base (emacsql-connection)
  ((file :initarg :file
         :initform nil
         :type (or null string)
         :documentation "Database file name.")
   (types :allocation :class
          :reader emacsql-types
          :initform '((integer "INTEGER")
                      (float "REAL")
                      (object "TEXT")
                      (nil nil))))
  :abstract t)

;;; Constants

(defconst emacsql-sqlite-reserved
  '( ABORT ACTION ADD AFTER ALL ALTER ANALYZE AND AS ASC ATTACH
     AUTOINCREMENT BEFORE BEGIN BETWEEN BY CASCADE CASE CAST CHECK
     COLLATE COLUMN COMMIT CONFLICT CONSTRAINT CREATE CROSS
     CURRENT_DATE CURRENT_TIME CURRENT_TIMESTAMP DATABASE DEFAULT
     DEFERRABLE DEFERRED DELETE DESC DETACH DISTINCT DROP EACH ELSE END
     ESCAPE EXCEPT EXCLUSIVE EXISTS EXPLAIN FAIL FOR FOREIGN FROM FULL
     GLOB GROUP HAVING IF IGNORE IMMEDIATE IN INDEX INDEXED INITIALLY
     INNER INSERT INSTEAD INTERSECT INTO IS ISNULL JOIN KEY LEFT LIKE
     LIMIT MATCH NATURAL NO NOT NOTNULL NULL OF OFFSET ON OR ORDER
     OUTER PLAN PRAGMA PRIMARY QUERY RAISE RECURSIVE REFERENCES REGEXP
     REINDEX RELEASE RENAME REPLACE RESTRICT RIGHT ROLLBACK ROW
     SAVEPOINT SELECT SET TABLE TEMP TEMPORARY THEN TO TRANSACTION
     TRIGGER UNION UNIQUE UPDATE USING VACUUM VALUES VIEW VIRTUAL WHEN
     WHERE WITH WITHOUT)
  "List of all of SQLite's reserved words.
Also see http://www.sqlite.org/lang_keywords.html.")

(defconst emacsql-sqlite-error-codes
  '((1  SQLITE_ERROR      emacsql-error      "SQL logic error")
    (2  SQLITE_INTERNAL   emacsql-internal   nil)
    (3  SQLITE_PERM       emacsql-access     "access permission denied")
    (4  SQLITE_ABORT      emacsql-error      "query aborted")
    (5  SQLITE_BUSY       emacsql-locked     "database is locked")
    (6  SQLITE_LOCKED     emacsql-locked     "database table is locked")
    (7  SQLITE_NOMEM      emacsql-memory     "out of memory")
    (8  SQLITE_READONLY   emacsql-access     "attempt to write a readonly database")
    (9  SQLITE_INTERRUPT  emacsql-error      "interrupted")
    (10 SQLITE_IOERR      emacsql-access     "disk I/O error")
    (11 SQLITE_CORRUPT    emacsql-corruption "database disk image is malformed")
    (12 SQLITE_NOTFOUND   emacsql-error      "unknown operation")
    (13 SQLITE_FULL       emacsql-access     "database or disk is full")
    (14 SQLITE_CANTOPEN   emacsql-access     "unable to open database file")
    (15 SQLITE_PROTOCOL   emacsql-access     "locking protocol")
    (16 SQLITE_EMPTY      emacsql-corruption nil)
    (17 SQLITE_SCHEMA     emacsql-error      "database schema has changed")
    (18 SQLITE_TOOBIG     emacsql-error      "string or blob too big")
    (19 SQLITE_CONSTRAINT emacsql-constraint "constraint failed")
    (20 SQLITE_MISMATCH   emacsql-error      "datatype mismatch")
    (21 SQLITE_MISUSE     emacsql-error      "bad parameter or other API misuse")
    (22 SQLITE_NOLFS      emacsql-error      "large file support is disabled")
    (23 SQLITE_AUTH       emacsql-access     "authorization denied")
    (24 SQLITE_FORMAT     emacsql-corruption nil)
    (25 SQLITE_RANGE      emacsql-error      "column index out of range")
    (26 SQLITE_NOTADB     emacsql-corruption "file is not a database")
    (27 SQLITE_NOTICE     emacsql-warning    "notification message")
    (28 SQLITE_WARNING    emacsql-warning    "warning message"))
  "Alist mapping SQLite error codes to EmacSQL conditions.
Elements have the form (ERRCODE SYMBOLIC-NAME EMACSQL-ERROR
ERRSTR).  Also see https://www.sqlite.org/rescode.html.")

;;; Variables

(defvar emacsql-include-header nil
  "Whether to include names of columns as an additional row.
Never enable this globally, only let-bind it around calls to `emacsql'.
Currently only supported by `emacsql-sqlite-builtin-connection' and
`emacsql-sqlite-module-connection'.")

(defvar emacsql-sqlite-busy-timeout 20
  "Seconds to wait when trying to access a table blocked by another process.
See https://www.sqlite.org/c3ref/busy_timeout.html.")

;;; Utilities

(defun emacsql-sqlite-connection (variable file &optional setup use-module)
  "Return the connection stored in VARIABLE to the database in FILE.

If the value of VARIABLE is a live database connection, return that.

Otherwise open a new connection to the database in FILE and store the
connection in VARIABLE, before returning it.  If FILE is nil, use an
in-memory database.  Always enable support for foreign key constrains.
If optional SETUP is non-nil, it must be a function, which takes the
connection as only argument.  This function can be used to initialize
tables, for example.

If optional USE-MODULE is non-nil, then use the external module even
when Emacs was built with SQLite support.  This is intended for testing
purposes."
  (or (let ((connection (symbol-value variable)))
        (and connection (emacsql-live-p connection) connection))
      (set variable (emacsql-sqlite-open file nil setup use-module))))

(defun emacsql-sqlite-open (file &optional debug setup use-module)
  "Open a connection to the database stored in FILE using an SQLite back-end.

Automatically use the best available back-end, as returned by
`emacsql-sqlite-default-connection'.

If FILE is nil, use an in-memory database.  If optional DEBUG is
non-nil, log all SQLite commands to a log buffer, for debugging
purposes.  Always enable support for foreign key constrains.

If optional SETUP is non-nil, it must be a function, which takes the
connection as only argument.  This function can be used to initialize
tables, for example.

If optional USE-MODULE is non-nil, then use the external module even
when Emacs was built with SQLite support.  This is intended for testing
purposes."
  (when file
    (make-directory (file-name-directory file) t))
  (let* ((class (emacsql-sqlite-default-connection use-module))
         (connection (make-instance class :file file)))
    (when debug
      (emacsql-enable-debugging connection))
    (emacsql connection [:pragma (= foreign-keys on)])
    (when setup
      (funcall setup connection))
    connection))

(defun emacsql-sqlite-default-connection (&optional use-module)
  "Determine and return the best SQLite connection class.

Signal an error if none of the connection classes can be used.

If optional USE-MODULE is non-nil, then use the external module even
when Emacs was built with SQLite support.  This is intended for testing
purposes."
  (or (and (not use-module)
           (fboundp 'sqlite-available-p)
           (sqlite-available-p)
           (require 'emacsql-sqlite-builtin)
           'emacsql-sqlite-builtin-connection)
      (and (boundp 'module-file-suffix)
           module-file-suffix
           (condition-case nil
               ;; Failure modes:
               ;; 1. `libsqlite' shared library isn't available.
               ;; 2. User chooses to not compile `libsqlite'.
               ;; 3. `libsqlite' compilation fails.
               (and (require 'sqlite3)
                    (require 'emacsql-sqlite-module)
                    'emacsql-sqlite-module-connection)
             (error
              (display-warning 'emacsql "\
Since your Emacs does not come with
built-in SQLite support [1], but does support C modules, we can
use an EmacSQL backend that relies on the third-party `sqlite3'
package [2].

Please install the `sqlite3' Elisp package using your preferred
Emacs package manager, and install the SQLite shared library
using your distribution's package manager.  That package should
be named something like `libsqlite3' [3] and NOT just `sqlite3'.

The legacy backend, which uses a custom SQLite executable, has
been remove, so we can no longer fall back to that.

[1]: Supported since Emacs 29.1, provided it was not disabled
     with `--without-sqlite3'.
[2]: https://github.com/pekingduck/emacs-sqlite3-api
[3]: On Debian https://packages.debian.org/buster/libsqlite3-0")
              ;; The buffer displaying the warning might immediately
              ;; be replaced by another buffer, before the user gets
              ;; a chance to see it.  We cannot have that.
              (let (fn)
                (setq fn (lambda ()
                           (remove-hook 'post-command-hook fn)
                           (pop-to-buffer (get-buffer "*Warnings*"))))
                (add-hook 'post-command-hook fn))
              nil)))
      (error "EmacSQL could not find or compile a back-end")))

(defun emacsql-sqlite-set-busy-timeout (connection)
  (when emacsql-sqlite-busy-timeout
    (emacsql connection [:pragma (= busy-timeout $s1)]
             (* emacsql-sqlite-busy-timeout 1000))))

(defun emacsql-sqlite-read-column (string)
  (let ((value nil)
        (beg 0)
        (end (length string)))
    (while (< beg end)
      (let ((v (read-from-string string beg)))
        (push (car v) value)
        (setq beg (cdr v))))
    (nreverse value)))

(defun emacsql-sqlite-list-tables (connection)
  "Return a list of symbols identifying tables in CONNECTION.
Tables whose names begin with \"sqlite_\", are not included
in the returned value."
  (mapcar #'car
          (emacsql connection
                   [:select name
                    ;; The new name is `sqlite-schema', but this name
                    ;; is supported by old and new SQLite versions.
                    ;; See https://www.sqlite.org/schematab.html.
                    :from sqlite-master
                    :where (and (= type 'table)
                                (not-like name "sqlite_%"))
                    :order-by [(asc name)]])))

(defun emacsql-sqlite-dump-database (connection &optional versionp)
  "Dump the database specified by CONNECTION to a file.

The dump file is placed in the same directory as the database
file and its name derives from the name of the database file.
The suffix is replaced with \".sql\" and if optional VERSIONP is
non-nil, then the database version (the `user_version' pragma)
and a timestamp are appended to the file name.

Dumping is done using the official `sqlite3' binary.  If that is
not available and VERSIONP is non-nil, then the database file is
copied instead."
  (let* ((version (caar (emacsql connection [:pragma user-version])))
         (db (oref connection file))
         (db (if (symbolp db) (symbol-value db) db))
         (name (file-name-nondirectory db))
         (output (concat (file-name-sans-extension db)
                         (and versionp
                              (concat (format "-v%s" version)
                                      (format-time-string "-%Y%m%d-%H%M")))
                         ".sql")))
    (cond
     ((locate-file "sqlite3" exec-path)
      (when (and (file-exists-p output) versionp)
        (error "Cannot dump database; %s already exists" output))
      (with-temp-file output
        (message "Dumping %s database to %s..." name output)
        (unless (zerop (save-excursion
                         (call-process "sqlite3" nil t nil db ".dump")))
          (error "Failed to dump %s" db))
        (when version
          (insert (format "PRAGMA user_version=%s;\n" version)))
        ;; The output contains "PRAGMA foreign_keys=OFF;".
        ;; Change that to avoid alarming attentive users.
        (when (re-search-forward "^PRAGMA foreign_keys=\\(OFF\\);" 1000 t)
          (replace-match "ON" t t nil 1))
        (message "Dumping %s database to %s...done" name output)))
     (versionp
      (setq output (concat (file-name-sans-extension output) ".db"))
      (message "Cannot dump database because sqlite3 binary cannot be found")
      (when (and (file-exists-p output) versionp)
        (error "Cannot copy database; %s already exists" output))
      (message "Copying %s database to %s..." name output)
      (copy-file db output)
      (message "Copying %s database to %s...done" name output))
     ((error "Cannot dump database; sqlite3 binary isn't available")))))

(defun emacsql-sqlite-restore-database (db dump)
  "Restore database DB from DUMP.

DUMP is a file containing SQL statements.  DB can be the file
in which the database is to be stored, or it can be a database
connection.  In the latter case the current database is first
dumped to a new file and the connection is closed.  Then the
database is restored from DUMP.  No connection to the new
database is created."
  (unless (stringp db)
    (emacsql-sqlite-dump-database db t)
    (emacsql-close (prog1 db (setq db (oref db file)))))
  (with-temp-buffer
    (unless (zerop (call-process "sqlite3" nil t nil db
                                 (format ".read %s" dump)))
      (error "Failed to read %s: %s" dump (buffer-string)))))

(provide 'emacsql-sqlite)

;;; emacsql-sqlite.el ends here
