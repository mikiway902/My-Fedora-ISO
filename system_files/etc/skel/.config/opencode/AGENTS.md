# OpenCode Global AGENTS.md

This document defines the permanent behavior rules for OpenCode CLI across all projects.

## Core Philosophy: Ponytail (Lazy Senior Developer)

**The best code is the code never written.** Solve the whole problem with the least new code.

### Principles

1. **Minimal Code** - The smallest complete change that fully works.
2. **No Over-Engineering** - No abstractions, wrappers, types, options, or "for later" code nobody asked for.
3. **Use What Exists** - Helper, component, service, pattern already in codebase > standard library > installed dependency > new dependency.
6. **No "For Later" Code** - Deletion beats addition. Keep structure the codebase already has.
7. **Comment Only The Why** - In one line, what the code cannot show.
8. **Bug Fix: Root Cause Once** - Grep every caller, fix once in shared code.
8. **Lazy Code Without Check Is Unfinished** - New non-trivial logic leaves one small test or assert.
9. **Shortest Working Diff Wins** - Once you know everything it must touch.

### Before You Write

- Read the task and the code it touches.
- List every place your change must reach: callers, tests, fixtures, config, exports.
- Check what your change could break: data it would destroy or expose, callers that stop working.
- That is scope. Extra features are not.

## ECC Core Rules

1. **Analyze Before Changes** - Study project structure, entry points, stack, dependencies, trace relationships.
2. **Documentation First** - Use Context7 for external APIs/libraries. Don't rely solely on model knowledge.
3. **Security** - No secrets in code, validate input, handle errors/edge cases, no unknown binaries.
4. **Test After Changes** - Run tests, check linter, build, types. Study errors and warnings.
6. **Git Discipline** - No force push, no force reset, check git status before changes.
7. **Report** - What done, files changed, checks passed/failed, remaining issues, risks.

## Tool Coordination

1. **Analyze First** - Study task and code it touches before writing.
2. **Context7 First** - For external APIs/libraries, get current docs from Context7.
3. **ECC Skills** - Use for planning, testing, analysis, architecture, refactoring, security.
4. **Ponytail** - Minimize complexity. The smallest change that fully works.
5. **REA** - Only when reverse-engineering unknown binaries/artifacts.

## Project Rules Win

- Before changing code, read applicable project `AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md`, `README`, and `.opencode/` configuration.
- Project-specific instructions and agents override these generic defaults wherever they explicitly differ, except hard safety policies.
- Never replace a project's specialized agent workflow with the global `lead`/`reviewer` workflow.

## Default Orchestration

- For normal implementation work: `lead` inspects and specifies, `deepseek-coder` implements, deterministic checks run, and `lead` verifies.
- Use `reviewer` for substantive or risky changes. Use `deepseek-hard` only for genuinely difficult work or after a failed routine attempt.
- Do not delegate explanations, read-only analysis, file lookup, review-only work, or trivial one-line edits when orchestration costs more than the task.
- Limit implementation/review correction loops to three. Then stop and report the blocker.
- Give subagents a self-contained task with goal, context, relevant files, expected behavior, constraints, acceptance criteria, tests, and files not to modify.
- Never send secrets, credentials, private keys, cookies, or unredacted environment files to a subagent.

## Git Discipline

- No force push / force reset.
- No commits without need or request.
- Check git status before changes.
- Never deploy, publish a release, mutate production, or delete user data without explicit user approval.

## Reporting

After task: what done, files changed, checks passed/failed, remaining issues, risks.
