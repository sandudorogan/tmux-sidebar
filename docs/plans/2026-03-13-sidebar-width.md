# Sidebar Width Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a documented tmux width setting for the sidebar, reduce the default width from 40 to 35, and keep the existing environment override path.

**Architecture:** The width resolution stays inside `scripts/ensure-sidebar-pane.sh`, which already owns sidebar creation. The script will read a tmux option for plugin users, preserve the `TMUX_SIDEBAR_WIDTH` environment override for lower-level control and tests, and fall back to a new default width of 35. Shell tests and README documentation will be updated alongside the script change.

**Tech Stack:** Bash, tmux options, shell test harness

---

### Task 1: Add failing tests for sidebar width resolution

**Files:**
- Modify: `tests/toggle_sidebar_test.sh`
- Modify: `tests/ensure_sidebar_pane_test.sh`

**Step 1: Write the failing test**

Add assertions that expect the new default width of `35`, and add a new test
case that sets `@tmux_sidebar_width` to a custom value and expects
`split-window ... -l <value>`.

**Step 2: Run test to verify it fails**

Run: `bash tests/run.sh tests/toggle_sidebar_test.sh tests/ensure_sidebar_pane_test.sh`
Expected: FAIL because the implementation still uses width `40` and does not
read `@tmux_sidebar_width`.

**Step 3: Write minimal implementation**

No implementation in this task.

**Step 4: Run test to verify it still fails for the expected reason**

Run: `bash tests/run.sh tests/toggle_sidebar_test.sh tests/ensure_sidebar_pane_test.sh`
Expected: FAIL only on width assertions.

**Step 5: Commit**

Commit later with implementation.

### Task 2: Implement sidebar width configuration

**Files:**
- Modify: `scripts/ensure-sidebar-pane.sh`

**Step 1: Write the failing test**

Covered by Task 1.

**Step 2: Run test to verify it fails**

Covered by Task 1.

**Step 3: Write minimal implementation**

Read `@tmux_sidebar_width` via `tmux show-options -gv`, use
`TMUX_SIDEBAR_WIDTH` first if set, and default to `35` when neither override is
present.

**Step 4: Run test to verify it passes**

Run: `bash tests/run.sh tests/toggle_sidebar_test.sh tests/ensure_sidebar_pane_test.sh`
Expected: PASS

**Step 5: Commit**

Commit later with docs once verification is complete.

### Task 3: Document width configuration

**Files:**
- Modify: `README.md`

**Step 1: Write the failing test**

Documentation-only task; no automated failure.

**Step 2: Run test to verify it fails**

Not applicable.

**Step 3: Write minimal implementation**

Document the default width of `35`, the `@tmux_sidebar_width` tmux option, and
the `TMUX_SIDEBAR_WIDTH` environment override.

**Step 4: Run test to verify it passes**

Run: `bash tests/run.sh`
Expected: PASS

**Step 5: Commit**

```bash
git add docs/plans/2026-03-13-sidebar-width-design.md docs/plans/2026-03-13-sidebar-width.md tests/toggle_sidebar_test.sh tests/ensure_sidebar_pane_test.sh scripts/ensure-sidebar-pane.sh README.md
git commit -m "feat: add configurable sidebar width"
```
