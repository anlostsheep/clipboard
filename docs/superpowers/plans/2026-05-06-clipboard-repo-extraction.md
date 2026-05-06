# Clipboard Repo Extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract `macos-clipboard-manager/` from `agent-learning-skills` into a standalone git repo at `/Users/lostsheep/programing/projects/clipboard`, carrying over 37 commits with paths elevated to root, push to `https://github.com/anlostsheep/clipboard.git`, and remove the directory from the original repo via a single new commit.

**Architecture:** Clone the original repo to a throwaway temp directory → run `git filter-repo` to keep only clipboard files and rewrite paths to root → merge the GitHub-created LICENSE commit → push to remote → clean up original repo with a deletion commit.

**Tech Stack:** `git`, `git-filter-repo` (Homebrew), `gh` CLI (optional, for auth), Bash

**Spec:** `docs/superpowers/specs/2026-05-06-clipboard-repo-extraction-design.md`

---

## Task 1: Install git-filter-repo

**Files:** none (environment setup)

- [ ] **Step 1: Check if git-filter-repo is already installed**

```bash
git filter-repo --version
```

Expected output: version string like `git filter-repo==2.x.x`  
If not found: proceed to Step 2. If found: skip to Task 2.

- [ ] **Step 2: Install via Homebrew**

```bash
brew install git-filter-repo
```

Expected: installation completes without error.

- [ ] **Step 3: Confirm installation**

```bash
git filter-repo --version
```

Expected: version string printed. No error.

---

## Task 2: Verify GitHub Authentication

**Files:** none (auth setup)

- [ ] **Step 1: Check GitHub CLI auth status**

```bash
gh auth status
```

Expected: `Logged in to github.com as anlostsheep`  
If not logged in: proceed to Step 2A.  
If `gh` is not installed: proceed to Step 2B (SSH).

- [ ] **Step 2A (if gh not authenticated): Login with GitHub CLI**

```bash
gh auth login
```

Follow the prompts: select `GitHub.com` → `HTTPS` → authenticate via browser. After completion, re-run Step 1 to confirm.

- [ ] **Step 2B (if using SSH instead): Verify SSH key**

```bash
ssh -T git@github.com
```

Expected: `Hi anlostsheep! You've successfully authenticated`  
If failed: add your public key (`~/.ssh/id_*.pub`) to GitHub → Settings → SSH and GPG keys → New SSH key, then retry.

> If using SSH, note that remote URLs in later tasks should use `git@github.com:anlostsheep/clipboard.git` instead of the HTTPS URL.

---

## Task 3: Extract Clipboard Repo (Phase 1)

**Files:**
- Creates: `/Users/lostsheep/programing/projects/clipboard/` (new git repo)
- Temp: `/tmp/clipboard-extract/` (deleted after move)

- [ ] **Step 1: Confirm source repo is clean**

```bash
cd /Users/lostsheep/programing/projects/agent-learning-skills
git status
```

Expected: `nothing to commit, working tree clean`  
If dirty: commit or stash changes before proceeding.

- [ ] **Step 2: Remove any previous temp extraction**

```bash
rm -rf /tmp/clipboard-extract
```

No output expected.

- [ ] **Step 3: Clone the source repo to a throwaway copy**

```bash
git clone /Users/lostsheep/programing/projects/agent-learning-skills /tmp/clipboard-extract
```

Expected: `Cloning into '/tmp/clipboard-extract'...` followed by success message.

- [ ] **Step 4: Run filter-repo to extract and rewrite paths**

```bash
cd /tmp/clipboard-extract
git filter-repo --path macos-clipboard-manager/ \
                --path-rename macos-clipboard-manager/: \
                --tag-rename '':''
```

Expected: completes without error. May print a progress summary.

- [ ] **Step 5: Verify extraction before moving**

```bash
# Commit count should be 37
git log --oneline | wc -l

# Root-level structure should be elevated correctly
ls

# No macos-clipboard-manager/ subdirectory should exist
ls macos-clipboard-manager 2>&1
```

Expected:
- `wc -l` → `37`
- `ls` → shows `Sources  Tests  Docs  Scripts  Assets  Package.swift` (no `macos-clipboard-manager/`)
- `ls macos-clipboard-manager` → `ls: macos-clipboard-manager: No such file or directory`

If commit count is wrong or `macos-clipboard-manager/` still exists, do NOT proceed — re-run Step 4 after removing `/tmp/clipboard-extract` and re-cloning.

- [ ] **Step 6: Move result to target directory**

```bash
# Ensure parent directory exists
ls /Users/lostsheep/programing/projects/

# Move
mv /tmp/clipboard-extract /Users/lostsheep/programing/projects/clipboard
```

Expected: no error.

- [ ] **Step 7: Verify final directory**

```bash
cd /Users/lostsheep/programing/projects/clipboard
ls
git log --oneline | head -3
git log --oneline | tail -3
```

Expected:
- `ls` shows `Sources  Tests  Docs  Scripts  Assets  Package.swift`
- `git log` shows clipboard-related commit messages at both ends

---

## Task 4: Connect to GitHub Remote (Phase 2)

**Files:** none (remote configuration)

- [ ] **Step 1: Add the GitHub remote**

```bash
cd /Users/lostsheep/programing/projects/clipboard
git remote add origin https://github.com/anlostsheep/clipboard.git
```

> If using SSH auth: use `git remote add origin git@github.com:anlostsheep/clipboard.git` instead.

No output expected.

- [ ] **Step 2: Confirm remote is set**

```bash
git remote -v
```

Expected:
```
origin  https://github.com/anlostsheep/clipboard.git (fetch)
origin  https://github.com/anlostsheep/clipboard.git (push)
```

- [ ] **Step 3: Fetch the GitHub initial commit (LICENSE)**

```bash
git fetch origin
```

Expected: fetches 1 commit (the Apache 2.0 LICENSE file GitHub created).

- [ ] **Step 4: Merge the LICENSE commit into local main**

```bash
git merge origin/main --allow-unrelated-histories \
    -m "chore: merge initial LICENSE from GitHub"
```

Expected: merge succeeds, `LICENSE` file appears in working directory.  
If a conflict appears: it should only involve `LICENSE` — accept the GitHub version:
```bash
git checkout origin/main -- LICENSE
git add LICENSE
git commit -m "chore: merge initial LICENSE from GitHub"
```

- [ ] **Step 5: Verify LICENSE is present**

```bash
ls LICENSE
head -3 LICENSE
```

Expected: file exists, first line reads `Apache License`.

- [ ] **Step 6: Push to GitHub**

```bash
git push -u origin main
```

Expected: push succeeds with `Branch 'main' set up to track remote branch 'main' from 'origin'`.

- [ ] **Step 7: Verify remote push**

```bash
# Branch tracking
git branch -vv

# Commit count on remote matches local
git log --oneline origin/main | wc -l
git log --oneline | wc -l
```

Expected:
- `git branch -vv` shows `* main ... [origin/main]`
- Both `wc -l` values match (38: 37 extracted + 1 LICENSE merge commit)

---

## Task 5: Clean Up Original Repo (Phase 3)

**Files:**
- Modify: `/Users/lostsheep/programing/projects/agent-learning-skills/` (delete `macos-clipboard-manager/`)

- [ ] **Step 1: Navigate to original repo**

```bash
cd /Users/lostsheep/programing/projects/agent-learning-skills
git status
```

Expected: clean working tree.

- [ ] **Step 2: Stage deletion of clipboard directory**

```bash
git rm -r macos-clipboard-manager/
```

Expected: lists all deleted files, no errors.

- [ ] **Step 3: Confirm staged changes look correct**

```bash
git diff --staged --stat
```

Expected: only `macos-clipboard-manager/` files shown as deleted. No other modifications.

- [ ] **Step 4: Commit the deletion**

```bash
git commit -m "chore: extract clipboard manager to separate repo (github.com/anlostsheep/clipboard)"
```

Expected: commit succeeds.

- [ ] **Step 5: Verify directory is gone from working tree**

```bash
ls macos-clipboard-manager 2>&1
```

Expected: `ls: macos-clipboard-manager: No such file or directory`

- [ ] **Step 6: Verify history is preserved**

```bash
# Old commits still reference macos-clipboard-manager/
git log --oneline -- macos-clipboard-manager/ | wc -l
```

Expected: `37` (historical commits still visible even though directory is gone)

- [ ] **Step 7: Verify HEAD commit is the deletion**

```bash
git log --oneline -1
```

Expected: `chore: extract clipboard manager to separate repo (github.com/anlostsheep/clipboard)`
