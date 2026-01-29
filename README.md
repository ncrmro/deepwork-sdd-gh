# deepwork-sdd-gh

Demonstrates using [deepwork](https://github.com/Unsupervisedcom/deepwork) and a local coding agent (Claude Code) to manage multiple streams of work via spec-driven development (SDD) on GitHub.

Markdown specs in the repo drive GitHub Issues, which drive agent-assigned work (GitHub Copilot agent or future local subagents), which produce PRs — all orchestrated from a single terminal session.

## User Stories

### US-1: Spec-to-Issue Sync

**As a** developer managing a feature spec
**I want** a GitHub Action to automatically create and update a tracking issue from my spec's `tasks.md`
**So that** merged progress in specs is reflected as issue state without manual bookkeeping

**Acceptance Criteria:**
- [ ] A GitHub Action triggers on pushes to the default branch that touch files under `specs/`
- [ ] For each spec, a single GitHub Issue is created (or updated if it already exists)
- [ ] Task completion checkboxes in `tasks.md` are mirrored to the issue body
- [ ] The issue title and labels identify which spec it tracks

### US-2: Issue-to-Agent Work Assignment

**As a** developer orchestrating implementation
**I want** to split a spec tracking issue into child issues assigned to Copilot agent (or create agent tasks directly)
**So that** parallelizable work is delegated to agents without leaving my terminal

**Acceptance Criteria:**
- [ ] From the local agent, I can create child issues from a spec's task list
- [ ] Child issues can be assigned to GitHub Copilot agent
- [ ] Copilot agent produces PRs with implementation for assigned issues
- [ ] The parent tracking issue links to child issues and their PRs

### US-3: PR Progress Monitoring

**As a** developer supervising agent-created PRs
**I want** to check PR status, CI results, and failing jobs from my local agent
**So that** I can monitor multiple streams of work without switching to the GitHub UI

**Acceptance Criteria:**
- [ ] The local agent can list open PRs for the repo with their CI status
- [ ] The local agent can retrieve failing CI job logs
- [ ] The local agent can summarize what went wrong in a failed check

### US-4: CI Artifact Retrieval and Agent Feedback

**As a** developer fixing CI failures on agent PRs
**I want** to download CI artifacts (e2e screenshots, logs) locally and provide them as context in PR comments to the agent
**So that** the agent can fix issues with rich context instead of me manually copying logs from the UI

**Acceptance Criteria:**
- [ ] The local agent can download GitHub Actions artifacts (screenshots, test reports) for a given PR
- [ ] Downloaded artifacts (especially images) can be viewed or referenced locally
- [ ] The local agent can post a PR review comment that includes the failure context and instructions for the agent to fix
- [ ] This closes the feedback loop: agent PR -> CI fails -> local agent reviews artifacts -> posts fix instructions -> agent pushes fix

### US-5: Single-Terminal Workflow

**As a** developer
**I want** to manage all of the above from one terminal session
**So that** I stay in flow and avoid context-switching across browser tabs and UIs

**Acceptance Criteria:**
- [ ] All operations (spec sync, issue creation, PR monitoring, artifact download, comment posting) are available via the local agent's tool set
- [ ] No GitHub UI interaction is required for the core workflow

## Functional Requirements

| ID | Requirement | Priority | User Story |
|----|-------------|----------|------------|
| FR-1 | GitHub Action watches `specs/` on the default branch for changes | Must Have | US-1 |
| FR-2 | Action parses `tasks.md` to extract task status (checked/unchecked) | Must Have | US-1 |
| FR-3 | Action creates a GitHub Issue per spec if one does not exist | Must Have | US-1 |
| FR-4 | Action updates the existing issue body when `tasks.md` changes | Must Have | US-1 |
| FR-5 | Action uses a label or naming convention to correlate specs to issues | Must Have | US-1 |
| FR-6 | Local agent can create child issues from a spec's task breakdown | Must Have | US-2 |
| FR-7 | Local agent can assign child issues to Copilot agent | Must Have | US-2 |
| FR-8 | Local agent can list open PRs with CI check status | Must Have | US-3 |
| FR-9 | Local agent can fetch CI job logs for a failing run | Must Have | US-3 |
| FR-10 | Local agent can download GitHub Actions artifacts for a PR | Must Have | US-4 |
| FR-11 | Local agent can post PR review comments with failure context | Must Have | US-4 |
| FR-12 | All operations work via CLI / agent tooling without browser UI | Should Have | US-5 |

## Plan

### Architecture Overview

```
specs/
  feature-name/
    spec.md          # functional spec (written via deepwork SDD job)
    plan.md          # technical plan
    tasks.md         # ordered task breakdown with checkboxes

.github/
  workflows/
    spec-sync.yml    # GitHub Action: specs/ -> GitHub Issues
```

### Component Breakdown

**1. GitHub Action — Spec Sync (`spec-sync.yml`)**

- Triggers on push to the default branch when files under `specs/` change
- For each spec directory, reads `tasks.md` and parses markdown checkboxes
- Searches for an existing issue by label (e.g., `spec:<feature-name>`)
- Creates or updates the issue with current task status
- Links to the spec files in the issue body for reference

**2. Local Agent Workflows (Claude Code with GitHub MCP)**

The local agent leverages existing tools (GitHub MCP server, `gh` CLI) — no custom tooling needed for the MVP:

- **Issue management**: Use `gh issue create`, GitHub MCP `issue_write`, and `sub_issue_write` to create and link child issues from task lists
- **Agent assignment**: Use `mcp__github__assign_copilot_to_issue` to delegate work to Copilot agent
- **PR monitoring**: Use `mcp__github__list_pull_requests`, `pull_request_read` (status, diff, comments) to check progress
- **CI inspection**: Use `gh run view`, `gh run view --log-failed` to retrieve failing job logs
- **Artifact download**: Use `gh run download` to pull artifacts (screenshots, test reports) locally
- **Feedback loop**: Use `mcp__github__add_issue_comment` or `pull_request_review_write` to post fix instructions with artifact context

**3. Spec-Driven Development via Deepwork**

Specs are authored using the [deepwork SDD job](https://github.com/Unsupervisedcom/deepwork/tree/main/library/jobs/spec_driven_development), which provides a structured six-step workflow: constitution, specify, clarify, plan, tasks, implement. This project adds the GitHub Issue tracking and agent orchestration layer on top.

### Scope

**In Scope (MVP)**
- GitHub Action for spec-to-issue sync
- Local agent workflows using existing `gh` CLI and GitHub MCP tools
- Copilot agent as the remote execution agent
- Single-repo, single-default-branch model

**Out of Scope**
- Git worktree-based local subagents
- Multi-repo orchestration
- Custom MCP server or deepwork plugin development
- Web UI or dashboard

## Tasks

### Phase 1: GitHub Action — Spec Sync

#### Task 1: Create spec-sync GitHub Action workflow

**User Story**: US-1
**Type**: Infrastructure
**Dependencies**: None

**Description:**
Create `.github/workflows/spec-sync.yml` that triggers on pushes to the default branch when files under `specs/` change. The workflow should enumerate spec directories and, for each, parse `tasks.md` for checkbox status.

**Files to Create:**
- `.github/workflows/spec-sync.yml` — workflow definition

**Acceptance Criteria:**
- [ ] Workflow triggers only on changes to `specs/**`
- [ ] Workflow detects which spec directories were modified
- [ ] Workflow parses `tasks.md` checkbox state (checked vs unchecked)

---

#### Task 2: Implement issue create/update logic in the Action

**User Story**: US-1
**Type**: Infrastructure
**Dependencies**: Task 1

**Description:**
Add logic to the workflow (inline script or action) that searches for an existing issue by label `spec:<feature-name>`, creates one if missing, or updates the body if it exists. The issue body should contain the current task status from `tasks.md` and links to the spec files.

**Files to Modify:**
- `.github/workflows/spec-sync.yml` — add issue sync logic

**Acceptance Criteria:**
- [ ] Issue is created with label `spec:<feature-name>` on first sync
- [ ] Issue body shows task completion status from `tasks.md`
- [ ] Issue body links to `spec.md`, `plan.md`, and `tasks.md` in the repo
- [ ] Subsequent pushes update the same issue rather than creating duplicates

---

### Phase 2: Example Spec

#### Task 3: Create an example spec to test the workflow

**User Story**: US-1
**Type**: Documentation
**Dependencies**: None (can run in parallel with Phase 1)
**Parallel**: [P]

**Description:**
Create a sample spec directory with `spec.md`, `plan.md`, and `tasks.md` to exercise the GitHub Action. The tasks should have a mix of checked and unchecked items.

**Files to Create:**
- `specs/example-feature/spec.md`
- `specs/example-feature/plan.md`
- `specs/example-feature/tasks.md`

**Acceptance Criteria:**
- [ ] Example spec follows the deepwork SDD format
- [ ] `tasks.md` has at least 3 tasks, some checked and some unchecked
- [ ] Pushing this to the default branch triggers the spec-sync action

---

### Phase 3: Documentation — Agent Workflows

#### Task 4: Document the local agent workflow for issue management and agent assignment

**User Story**: US-2, US-5
**Type**: Documentation
**Dependencies**: Task 2

**Description:**
Document the step-by-step commands and agent interactions for: creating child issues from a spec, assigning to Copilot agent, and linking back to the parent tracking issue. This serves as a runbook for using the local agent.

**Files to Create/Modify:**
- `docs/workflows/agent-orchestration.md`

**Acceptance Criteria:**
- [ ] Documents how to create child issues from task breakdown
- [ ] Documents how to assign Copilot agent to issues
- [ ] Documents how to check parent/child issue linkage

---

#### Task 5: Document the local agent workflow for PR monitoring and CI feedback

**User Story**: US-3, US-4, US-5
**Type**: Documentation
**Dependencies**: Task 2

**Description:**
Document the step-by-step commands for: listing PRs with status, fetching failing CI logs, downloading artifacts, and posting fix-context comments on PRs.

**Files to Create/Modify:**
- `docs/workflows/ci-feedback-loop.md`

**Acceptance Criteria:**
- [ ] Documents how to list PRs and check CI status
- [ ] Documents how to retrieve failing job logs
- [ ] Documents how to download and review artifacts (screenshots, reports)
- [ ] Documents how to post PR comments with failure context for the agent

---

## Summary

| Phase | Tasks | Parallel |
|-------|-------|----------|
| 1. GitHub Action | 1–2 | 0 |
| 2. Example Spec | 3 | 1 (with Phase 1) |
| 3. Documentation | 4–5 | 1 (tasks 4 and 5 are independent) |

**Critical Path**: Task 1 → Task 2 → Task 4/5

**Total Tasks**: 5
**Parallelizable**: Task 3 with Phase 1; Tasks 4 and 5 with each other
