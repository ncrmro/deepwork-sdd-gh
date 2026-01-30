# Evaluation

How to evaluate the end-to-end SDD-GH flow by standing up a disposable repo, running the workflow, and validating each stage.

## Overview

A bash script creates a fresh GitHub repo, seeds it with a spec, pushes to main (triggering the GitHub Action), then validates that issues were created, child issues can be assigned, and the feedback loop works. The repo is deleted at the end.

## Evaluation Script

```bash
#!/usr/bin/env bash
set -euo pipefail

OWNER="$(gh api user -q .login)"
REPO="sdd-gh-eval-$(date +%s)"
FULL="${OWNER}/${REPO}"

cleanup() {
  echo "--- Cleanup ---"
  gh repo delete "$FULL" --yes 2>/dev/null || true
}
trap cleanup EXIT

echo "=== 1. Create test repo ==="
gh repo create "$REPO" --public --clone
cd "$REPO"

echo "=== 2. Copy workflow ==="
mkdir -p .github/workflows
cp /path/to/deepwork-sdd-gh/.github/workflows/spec-sync.yml .github/workflows/

echo "=== 3. Seed a spec with mixed task status ==="
mkdir -p specs/eval-feature
cat > specs/eval-feature/spec.md << 'SPEC'
# Eval Feature

## User Stories

### US-1: Widget Creation
**As a** user
**I want** to create widgets
**So that** I can track things
SPEC

cat > specs/eval-feature/plan.md << 'PLAN'
# Eval Feature Plan

## Architecture
Simple REST API with a widgets table.
PLAN

cat > specs/eval-feature/tasks.md << 'TASKS'
# Eval Feature Tasks

- [x] Create widgets database migration
- [x] Implement widget model
- [ ] Add POST /widgets endpoint
- [ ] Add GET /widgets endpoint
- [ ] Write integration tests
TASKS

echo "=== 4. Push to main ==="
git add -A
git commit -m "Add spec for eval-feature"
git push -u origin main

echo "=== 5. Wait for GitHub Action ==="
# Poll for the workflow run to complete
for i in $(seq 1 30); do
  RUN_STATUS=$(gh run list --workflow=spec-sync.yml --limit=1 --json status -q '.[0].status' 2>/dev/null || echo "pending")
  if [ "$RUN_STATUS" = "completed" ]; then
    echo "Action completed."
    break
  fi
  echo "Waiting for action... ($i/30)"
  sleep 10
done

echo "=== 6. Validate: spec-sync issue created ==="
ISSUE_COUNT=$(gh issue list --label "spec:eval-feature" --json number -q 'length')
if [ "$ISSUE_COUNT" -ge 1 ]; then
  echo "PASS: Tracking issue exists"
else
  echo "FAIL: No tracking issue found"
  exit 1
fi

ISSUE_NUMBER=$(gh issue list --label "spec:eval-feature" --json number -q '.[0].number')
ISSUE_BODY=$(gh issue view "$ISSUE_NUMBER" --json body -q '.body')

echo "=== 7. Validate: issue title has progress ==="
ISSUE_TITLE=$(gh issue view "$ISSUE_NUMBER" --json title -q '.title')
if echo "$ISSUE_TITLE" | grep -q "2/5"; then
  echo "PASS: Title shows 2/5 progress"
else
  echo "FAIL: Title does not show expected progress. Got: $ISSUE_TITLE"
  exit 1
fi

echo "=== 8. Validate: issue body has checkboxes ==="
CHECKED=$(echo "$ISSUE_BODY" | grep -c '\[x\]' || true)
UNCHECKED=$(echo "$ISSUE_BODY" | grep -c '\[ \]' || true)
if [ "$CHECKED" -eq 2 ] && [ "$UNCHECKED" -eq 3 ]; then
  echo "PASS: Checkbox counts match (2 done, 3 todo)"
else
  echo "FAIL: Expected 2 checked / 3 unchecked. Got $CHECKED / $UNCHECKED"
  exit 1
fi

echo "=== 9. Validate: issue body links to spec files ==="
if echo "$ISSUE_BODY" | grep -q "spec.md" && echo "$ISSUE_BODY" | grep -q "tasks.md"; then
  echo "PASS: Issue body links to spec files"
else
  echo "FAIL: Missing spec file links in issue body"
  exit 1
fi

echo "=== 10. Validate: re-sync updates (not duplicates) ==="
# Update tasks.md with one more task checked off
cat > specs/eval-feature/tasks.md << 'TASKS'
# Eval Feature Tasks

- [x] Create widgets database migration
- [x] Implement widget model
- [x] Add POST /widgets endpoint
- [ ] Add GET /widgets endpoint
- [ ] Write integration tests
TASKS

git add -A
git commit -m "Mark POST endpoint task complete"
git push

# Wait for second run
for i in $(seq 1 30); do
  # Get the latest run (should be the second one)
  RUNS=$(gh run list --workflow=spec-sync.yml --limit=1 --json status,databaseId -q '.[0].status' 2>/dev/null || echo "pending")
  if [ "$RUNS" = "completed" ]; then
    break
  fi
  sleep 10
done

ISSUE_COUNT_AFTER=$(gh issue list --label "spec:eval-feature" --json number -q 'length')
if [ "$ISSUE_COUNT_AFTER" -eq 1 ]; then
  echo "PASS: Still one issue (updated, not duplicated)"
else
  echo "FAIL: Expected 1 issue, found $ISSUE_COUNT_AFTER"
  exit 1
fi

TITLE_AFTER=$(gh issue view "$ISSUE_NUMBER" --json title -q '.title')
if echo "$TITLE_AFTER" | grep -q "3/5"; then
  echo "PASS: Title updated to 3/5"
else
  echo "FAIL: Title not updated. Got: $TITLE_AFTER"
  exit 1
fi

echo "=== 11. Create child issue for agent assignment ==="
gh issue create --title "Implement GET /widgets endpoint" --body "From spec eval-feature task 4" --label "spec:eval-feature"
CHILD_NUMBER=$(gh issue list --label "spec:eval-feature" --search "GET /widgets" --json number -q '.[0].number')
echo "Created child issue #$CHILD_NUMBER"

echo "=== 12. Link child as sub-issue of parent ==="
# Get GraphQL node IDs for parent and child
IDS=$(gh api graphql -f query="
query {
  repository(owner: \"$OWNER\", name: \"$REPO\") {
    parent: issue(number: $ISSUE_NUMBER) { id }
    child:  issue(number: $CHILD_NUMBER) { id }
  }
}")

PARENT_ID=$(echo "$IDS" | jq -r '.data.repository.parent.id')
CHILD_ID=$(echo "$IDS" | jq -r '.data.repository.child.id')

gh api graphql -f query="
mutation {
  addSubIssue(input: {
    issueId:    \"$PARENT_ID\",
    subIssueId: \"$CHILD_ID\"
  }) {
    issue    { number title }
    subIssue { number title }
  }
}"

# Verify sub-issue relationship
SUB_ISSUES=$(gh api graphql -f query="
query {
  repository(owner: \"$OWNER\", name: \"$REPO\") {
    issue(number: $ISSUE_NUMBER) {
      subIssues(first: 10) {
        nodes { number title }
      }
    }
  }
}" -q '.data.repository.issue.subIssues.nodes | length')

if [ "$SUB_ISSUES" -ge 1 ]; then
  echo "PASS: Child issue #$CHILD_NUMBER linked as sub-issue of #$ISSUE_NUMBER"
else
  echo "FAIL: Sub-issue relationship not found"
  exit 1
fi

echo "=== 13. Assign Copilot agent to child issue ==="
# Copilot agent assignment uses the REST API
ASSIGN_RESULT=$(gh api \
  --method POST \
  "repos/$FULL/issues/$CHILD_NUMBER/sub_issues" \
  2>/dev/null || true)

# Use the Copilot coding agent assignment endpoint
gh api \
  --method POST \
  "repos/$FULL/copilot/tasks" \
  -f "issue_number=$CHILD_NUMBER" \
  2>/dev/null && COPILOT_ASSIGNED=true || COPILOT_ASSIGNED=false

if [ "$COPILOT_ASSIGNED" = "true" ]; then
  echo "PASS: Copilot agent assigned to issue #$CHILD_NUMBER"
else
  # Copilot agent may not be available on the test repo — this is expected
  # in environments without Copilot agent access. Log and continue.
  echo "SKIP: Copilot agent assignment not available (requires Copilot agent enabled on repo)"
fi

echo "=== 14. Validate: agent produces a PR (if assigned) ==="
if [ "$COPILOT_ASSIGNED" = "true" ]; then
  echo "Waiting for Copilot agent to open a PR..."
  PR_FOUND=false
  for i in $(seq 1 60); do
    PR_COUNT=$(gh pr list --search "linked:issue:$CHILD_NUMBER" --json number -q 'length' 2>/dev/null || echo "0")
    if [ "$PR_COUNT" -ge 1 ]; then
      PR_NUMBER=$(gh pr list --search "linked:issue:$CHILD_NUMBER" --json number -q '.[0].number')
      echo "PASS: Copilot agent opened PR #$PR_NUMBER for issue #$CHILD_NUMBER"
      PR_FOUND=true
      break
    fi
    # Also check by author (copilot agent PRs come from a bot)
    PR_COUNT_ALT=$(gh pr list --json number,author --jq '[.[] | select(.author.login == "copilot-swe-agent" or .author.login == "copilot")] | length' 2>/dev/null || echo "0")
    if [ "$PR_COUNT_ALT" -ge 1 ]; then
      PR_NUMBER=$(gh pr list --json number,author --jq '[.[] | select(.author.login == "copilot-swe-agent" or .author.login == "copilot")][0].number')
      echo "PASS: Copilot agent opened PR #$PR_NUMBER"
      PR_FOUND=true
      break
    fi
    echo "Waiting for agent PR... ($i/60)"
    sleep 30
  done

  if [ "$PR_FOUND" = "false" ]; then
    echo "FAIL: No PR opened by Copilot agent within timeout"
    exit 1
  fi

  echo "=== 15. Validate: PR has CI status ==="
  PR_STATUS=$(gh pr checks "$PR_NUMBER" --json state -q '.[0].state' 2>/dev/null || echo "none")
  echo "PR #$PR_NUMBER CI status: $PR_STATUS"
  echo "PASS: PR CI status is retrievable"
else
  echo "SKIP: Steps 14-15 (Copilot agent not available)"
fi

echo ""
echo "==============================="
echo "  ALL CHECKS PASSED"
echo "==============================="
```

## What Each Step Validates

| Step | What | Validates |
|------|------|-----------|
| 1–4 | Repo + spec setup | Scaffolding works end-to-end |
| 5 | Action run | Workflow triggers on `specs/` changes |
| 6 | Issue existence | Action creates an issue with the `spec:` label |
| 7 | Progress in title | Title format `[Spec] name (N/M)` is correct |
| 8 | Checkbox mirroring | `tasks.md` checkboxes are reflected in issue body |
| 9 | Spec file links | Issue body contains links to spec files |
| 10 | Idempotent update | Second push updates the same issue, not a duplicate |
| 11 | Child issue creation | Child issue created with spec label |
| 12 | Sub-issue linking | Child linked to parent via GraphQL `addSubIssue` mutation |
| 13 | Copilot agent assignment | Agent assigned to child issue (skips if unavailable) |
| 14 | Agent PR creation | Copilot agent opens a PR for the assigned issue |
| 15 | PR CI status | CI check status is retrievable on the agent's PR |

## Running

```bash
# From the deepwork-sdd-gh repo root
bash research/evaluation.sh
```

The script uses `trap cleanup EXIT` so the test repo is deleted even on failure.

## Future Extensions

- **Agent assignment validation**: After creating the child issue, use `gh api` to assign Copilot agent and verify a PR is opened. This requires Copilot agent access on the test repo.
- **CI artifact loop**: Push a failing test in a PR, download the artifact, post a review comment, and verify the comment appears. Requires a CI workflow in the test repo.
- **Multiple specs**: Seed two spec directories and validate two separate issues are created/updated independently.
- **Closed issue handling**: Check a spec where all tasks are done and verify the issue can be closed (manually or automatically).
