;;; emacs-local-rag.el --- Local RAG for Org-roam + GPTel -*- lexical-binding: t; -*-

(require 'json)
(require 'seq)
(require 'subr-x)

(defgroup emacs-local-rag nil
  "Local semantic retrieval for Org-mode notes inside Emacs."
  :group 'tools)

(defcustom emacs-local-rag-notes-directory nil
  "Directory containing Org notes to index."
  :type 'directory
  :group 'emacs-local-rag)

(defcustom emacs-local-rag-python-command "python3"
  "Python executable used to generate embeddings."
  :type 'string
  :group 'emacs-local-rag)

(defcustom emacs-local-rag-embedding-script nil
  "Absolute path to embeddings_local.py."
  :type 'file
  :group 'emacs-local-rag)

(defcustom emacs-local-rag-top-k 5
  "Number of retrieved chunks."
  :type 'integer
  :group 'emacs-local-rag)

(defcustom emacs-local-rag-chunk-size 1500
  "Maximum chunk size used during indexing."
  :type 'integer
  :group 'emacs-local-rag)

(defvar emacs-local-rag-index (make-hash-table :test 'equal)
  "In-memory vector index.
Each key is a file path and each value is a list of plists:
(:text CHUNK :embedding VECTOR).")

(defun emacs-local-rag--validate-config ()
  "Validate required user configuration."
  (unless (and emacs-local-rag-notes-directory
               (file-directory-p emacs-local-rag-notes-directory))
    (user-error "Set `emacs-local-rag-notes-directory` to a valid folder"))
  (unless (and emacs-local-rag-embedding-script
               (file-exists-p emacs-local-rag-embedding-script))
    (user-error "Set `emacs-local-rag-embedding-script` to embeddings_local.py")))

(defun emacs-local-rag--compute-embedding (text)
  "Generate an embedding for TEXT using the Python helper script."
  (with-temp-buffer
    (let* ((input-file (make-temp-file "emacs-local-rag-in-" nil ".txt" text))
           (output-file (make-temp-file "emacs-local-rag-out-" nil ".json"))
           (cmd (format "%s %s %s %s"
                        (shell-quote-argument emacs-local-rag-python-command)
                        (shell-quote-argument emacs-local-rag-embedding-script)
                        (shell-quote-argument input-file)
                        (shell-quote-argument output-file)))
           (exit-code (let ((inhibit-message t))
                        (shell-command cmd))))
      (unwind-protect
          (when (and (= exit-code 0) (file-exists-p output-file))
            (erase-buffer)
            (insert-file-contents output-file)
            (let ((parsed (json-parse-string (buffer-string) :array-type 'list)))
              (apply #'vector (mapcar #'float parsed))))
        (when (file-exists-p input-file)
          (delete-file input-file))
        (when (file-exists-p output-file)
          (delete-file output-file))))))

(defun emacs-local-rag--chunk-text (text)
  "Split TEXT into fixed-size chunks."
  (let ((chunks nil)
        (start 0)
        (len (length text)))
    (while (< start len)
      (let ((end (min len (+ start emacs-local-rag-chunk-size))))
        (push (substring text start end) chunks)
        (setq start end)))
    (nreverse chunks)))

(defun emacs-local-rag--cosine (v1 v2)
  "Compute cosine similarity between V1 and V2."
  (let ((dot 0.0)
        (n1 0.0)
        (n2 0.0))
    (dotimes (i (min (length v1) (length v2)))
      (setq dot (+ dot (* (aref v1 i) (aref v2 i))))
      (setq n1 (+ n1 (* (aref v1 i) (aref v1 i))))
      (setq n2 (+ n2 (* (aref v2 i) (aref v2 i)))))
    (if (or (= n1 0.0) (= n2 0.0))
        0.0
      (/ dot (* (sqrt n1) (sqrt n2))))))

;;;###autoload
(defun emacs-local-rag-index-directory (dir)
  "Index all .org files inside DIR."
  (interactive
   (list
    (read-directory-name
     "Directory to index: "
     (or emacs-local-rag-notes-directory default-directory))))
  (emacs-local-rag--validate-config)
  (clrhash emacs-local-rag-index)
  (let ((files (directory-files-recursively dir "\\.org$")))
    (message "Indexing %d files..." (length files))
    (dolist (file files)
      (with-temp-buffer
        (insert-file-contents file)
        (let* ((full-text (buffer-string))
               (chunks (emacs-local-rag--chunk-text full-text))
               (indexed
                (delq nil
                      (mapcar
                       (lambda (chunk)
                         (let ((vec (emacs-local-rag--compute-embedding chunk)))
                           (when vec
                             (list :text chunk :embedding vec))))
                       chunks))))
          (when indexed
            (puthash file indexed emacs-local-rag-index)))))
    (message "Indexing complete. %d files loaded into memory."
             (hash-table-count emacs-local-rag-index))))

(defun emacs-local-rag-semantic-search (query)
  "Return top semantic matches for QUERY."
  (let* ((qvec (emacs-local-rag--compute-embedding query))
         (results '()))
    (when qvec
      (maphash
       (lambda (file chunks)
         (dolist (item chunks)
           (let ((sim (emacs-local-rag--cosine qvec (plist-get item :embedding))))
             (push (list :file file
                         :text (plist-get item :text)
                         :score sim)
                   results))))
       emacs-local-rag-index)
      (seq-take
       (sort results
             (lambda (a b)
               (> (plist-get a :score)
                  (plist-get b :score))))
       emacs-local-rag-top-k))))

(defun emacs-local-rag--format-context (results)
  "Format RESULTS into a context string."
  (if (and results (listp results))
      (string-join
       (mapcar
        (lambda (item)
          (format "--- [Note: %s] ---\n%s"
                  (file-name-nondirectory (plist-get item :file))
                  (plist-get item :text)))
        results)
       "\n\n")
    "No relevant context found."))

;;;###autoload
(defun emacs-local-rag-query-with-context (query)
  "Create a GPTel chat buffer with retrieved local context."
  (interactive "sQuestion: ")
  (unless (fboundp 'gptel-send)
    (user-error "GPTel is not installed or loaded"))
  (let* ((top (emacs-local-rag-semantic-search query))
         (context (emacs-local-rag--format-context top))
         (buffer-name "*GPTel Local RAG*"))
    (with-current-buffer (get-buffer-create buffer-name)
      (when (fboundp 'markdown-mode)
        (markdown-mode))
      (when (fboundp 'gptel-mode)
        (gptel-mode 1))
      (visual-line-mode 1)
      (erase-buffer)
      (insert "SYSTEM: You are a personal assistant. Use the context below to answer the user's question. If the answer is not in the context, say you do not know.\n\n")
      (insert "CONTEXT:\n" context "\n\n")
      (insert "---------------------------------------------------\n")
      (insert "QUESTION: " query "\n\n")
      (goto-char (point-max)))
    (pop-to-buffer buffer-name)
    (message "Context injected. Sending to GPTel...")
    (gptel-send)))

;;;###autoload
(defun emacs-local-rag-inline-edit-async ()
  "Use local retrieval + GPTel to rewrite region or generate code."
  (interactive)
  (unless (fboundp 'gptel-request)
    (user-error "GPTel is not installed or loaded"))
  (let* ((orig-buf (current-buffer))
         (has-region (use-region-p))
         (start-marker (if has-region
                           (copy-marker (region-beginning))
                         (point-marker)))
         (end-marker (if has-region
                         (copy-marker (region-end) t)
                       (copy-marker start-marker t)))
         (selection (when has-region
                      (buffer-substring-no-properties start-marker end-marker)))
         (instruction (read-string (if selection
                                       "Instruction: "
                                     "Generate code: ")))
         (ctx (ignore-errors
                (emacs-local-rag-semantic-search (or selection instruction))))
         (context-text (if (and ctx (listp ctx))
                           (string-join
                            (mapcar (lambda (item) (plist-get item :text)) ctx)
                            "\n\n")
                         ""))
         (prompt
          (concat
           (when (not (string-empty-p context-text))
             (format "CONTEXT:\n%s\n\n" context-text))
           (when selection
             (format "CODE:\n%s\n\n" selection))
           (format "INSTRUCTION:\n%s" instruction)))
         (system "You are an expert coder. Return only raw code."))
    (message "Processing...")
    (gptel-request
        prompt
      :system system
      :callback
      (lambda (response _info)
        (let ((resp-str (if (stringp response)
                            response
                          (format "%s" response))))
          (when (buffer-live-p orig-buf)
            (with-current-buffer orig-buf
              (save-excursion
                (goto-char start-marker)
                (when has-region
                  (delete-region start-marker end-marker))
                (insert (string-trim resp-str))
                (set-marker start-marker nil)
                (set-marker end-marker nil)
                (message "Done.")))))))))

(provide 'emacs-local-rag)
;;; emacs-local-rag.el ends here
