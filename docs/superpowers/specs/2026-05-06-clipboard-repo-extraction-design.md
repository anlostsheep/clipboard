# Design: Extract clipboard manager to standalone repo

**Date**: 2026-05-06  
**Status**: Approved

## Background

The `macos-clipboard-manager/` app was developed inside `agent-learning-skills` (a general agent learning monorepo). It has accumulated 37 git commits and is ready to live as an independent project.

## Goals

1. Create a new standalone git repo at `/Users/lostsheep/programing/projects/clipboard`
2. Carry over all 37 clipboard-related commits with paths elevated to repo root
3. Connect to new GitHub remote: `https://github.com/anlostsheep/clipboard.git`
4. Remove `macos-clipboard-manager/` from the original repo via a single new commit (history preserved)

## Out of Scope

- Rewriting history in `agent-learning-skills` (force push not required)
- Migrating CI/CD, branch protection rules, or issue trackers

## Tool

`git filter-repo` (install via `brew install git-filter-repo`)

## Directory Layout After Extraction

**New repo** (`/Users/lostsheep/programing/projects/clipboard`):
```
Sources/
Tests/
Docs/
Scripts/
Assets/
Package.swift
LICENSE          ← from GitHub initial commit
```

**Original repo** (`agent-learning-skills`): `macos-clipboard-manager/` removed, history intact.

## Implementation Steps

### Phase 1 — Extract new clipboard repo

```bash
# Clone a throwaway copy
git clone /Users/lostsheep/programing/projects/agent-learning-skills /tmp/clipboard-extract

# Filter: keep only macos-clipboard-manager/, rename paths to root
cd /tmp/clipboard-extract
git filter-repo --path macos-clipboard-manager/ \
                --path-rename macos-clipboard-manager/: \
                --tag-rename '':''

# Move result to target location
mv /tmp/clipboard-extract /Users/lostsheep/programing/projects/clipboard
```

### Phase 2 — Connect to GitHub remote

**Pre-check: GitHub authentication**

Before pushing, verify GitHub access:

```bash
# Option A: GitHub CLI (preferred)
gh auth status
# If not logged in: gh auth login

# Option B: SSH key
ssh -T git@github.com
# Output should include "Hi anlostsheep!"
# If not set up: add ~/.ssh/id_*.pub to GitHub → Settings → SSH keys
# Then switch remote URL to SSH:
# git remote set-url origin git@github.com:anlostsheep/clipboard.git

# Option C: HTTPS with Personal Access Token
# Create PAT at: GitHub → Settings → Developer settings → Tokens (classic)
# Scopes needed: repo
# Then credential helper will prompt for username + PAT on first push
```

Choose one auth method before proceeding. SSH is recommended for ongoing development.

```bash
cd /Users/lostsheep/programing/projects/clipboard

git remote add origin https://github.com/anlostsheep/clipboard.git
# (or SSH: git remote add origin git@github.com:anlostsheep/clipboard.git)
git fetch origin

# Merge the initial LICENSE commit from GitHub
git merge origin/main --allow-unrelated-histories \
    -m "chore: merge initial LICENSE from GitHub"

git push -u origin main
```

### Phase 3 — Clean up original repo

```bash
cd /Users/lostsheep/programing/projects/agent-learning-skills

git rm -r macos-clipboard-manager/
git commit -m "chore: extract clipboard manager to separate repo (github.com/anlostsheep/clipboard)"
```

## Verification

### After Phase 1 — Verify extraction

```bash
cd /Users/lostsheep/programing/projects/clipboard

# 1. Commit count should be 37
git log --oneline | wc -l

# 2. Root-level files should be elevated correctly
ls
# Expected: Sources/ Tests/ Docs/ Scripts/ Assets/ Package.swift

# 3. No macos-clipboard-manager/ subdirectory should exist
ls macos-clipboard-manager 2>&1 | grep "No such file"

# 4. Spot-check earliest and latest commit
git log --oneline | tail -3
git log --oneline | head -3
```

### After Phase 2 — Verify remote push

```bash
# 1. Remote is configured correctly
git remote -v
# Expected: origin  https://github.com/anlostsheep/clipboard.git (fetch/push)

# 2. Local main tracks origin/main
git branch -vv
# Expected: * main ... [origin/main]

# 3. GitHub has all commits
git log --oneline origin/main | wc -l
# Should match local: 37 + 1 (LICENSE merge commit) = 38

# 4. LICENSE file is present
ls LICENSE
```

### After Phase 3 — Verify original repo cleanup

```bash
cd /Users/lostsheep/programing/projects/agent-learning-skills

# 1. Directory no longer exists
ls macos-clipboard-manager 2>&1 | grep "No such file"

# 2. Deletion commit is present at HEAD
git log --oneline -1
# Expected: chore: extract clipboard manager to separate repo

# 3. Historical commits still visible (history preserved)
git log --oneline -- macos-clipboard-manager/ | wc -l
# Expected: 37 (old commits still in history)
```

## Key Properties

| Property | Value |
|----------|-------|
| Commits migrated | 37 (content, author, timestamp all preserved) |
| Path rewrite | `macos-clipboard-manager/X` → `X` |
| Original repo history | Preserved, one new deletion commit added |
| Remote (new repo) | `https://github.com/anlostsheep/clipboard.git` |
| License | Apache 2.0 (already on GitHub) |

## Risks

- `filter-repo` rewrites commit SHAs in the new repo — expected, not a problem for a brand new repo
- `--allow-unrelated-histories` merge: only one file (`LICENSE`) on the GitHub side, no conflicts expected
- Phase 3 commit requires pushing to Gitee; no force push needed
