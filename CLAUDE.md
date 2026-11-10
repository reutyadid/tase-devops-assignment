# CLAUDE.md — Working Rules

This repo is a **home assignment for a DevOps Engineer interview** (Tel Aviv Stock Exchange).
I will be interviewed on every line. My goal: a solution that **works end-to-end**, that I
**fully understand**, and that follows the assignment instructions **exactly**.

## Language
- Talk to me in **Hebrew**. Explain concepts simply, with the "why", not only the "what".
- Everything written in the repo (code, comments, docs, commit messages) is in **English**.

## Rule #1 — The assignment text is the spec
- The exact assignment text is in `REQUIREMENTS.md`. Never change its wording.
- Every requirement must map to a row in the matrix in `REQUIREMENTS.md`.
- Do NOT add features that are not required. If you think something extra is worth it,
  **suggest it and wait for my answer**. Do not build it on your own.
- If a requirement is ambiguous, stop and ask me. Write the interpretation we chose in `DECISIONS.md`.

## Rule #2 — Ask before you write
Work in small chunks (roughly one function / one file / one service at a time):
1. **Plan**: explain in Hebrew what you are about to write, why, and which alternatives exist.
2. **Wait** for my approval. Do not write code before I say go.
3. **Write** the chunk. Keep it short and readable.
4. **Explain** it: walk me through the important lines.
5. **Test**: give me the exact command to run and the expected output. I run it.
6. **Document**: update `DECISIONS.md` / `TROUBLESHOOTING.md` / the matrix if relevant.
7. **Review**: when a chunk is ready, tell me it is ready for `/review`. I run it,
   we fix the findings together, and then **I** commit and push.

**Only I run `git commit` and `git push`.** You never run them, never ask to run them,
and never try to work around this (it is also blocked in `.claude/settings.json`).
You may run read-only git commands (`git status`, `git diff`, `git log`) and suggest
`git add` paths + a commit message for me to use.

## Rule #3 — Research before significant decisions
Before any significant decision (tool choice, architecture, repo layout, image choice,
security approach), **search the web** for the current best practice and official docs.
Show me 2–3 options with short pros/cons and your recommendation. Prefer official
documentation over blogs. Record the final decision and source links in `DECISIONS.md`.

## Rule #4 — Simplicity over features
- Simple, readable, working end-to-end > many features I can't explain.
- Prefer standard, widely-used tools and default conventions.
- No clever tricks. If a line needs a long explanation, rewrite it simpler.
- Minimal dependencies. Pin versions.

## Rule #5 — Security (keep it simple, but never skip it)
- No secrets in the repo, ever. Use `.env` (git-ignored) + a committed `.env.example`.
- Pin image tags / package versions (no `latest`).
- Least privilege: non-root containers when it is simple to do, minimal ports exposed.
- Quote variables in shell scripts; validate inputs; `set -euo pipefail` where it fits.
- Run linters where relevant (`shellcheck`, `ansible-lint`, `hadolint`).
- Check `.gitignore` before every commit.

## Docs I keep in every task
- `README.md` — what it is, prerequisites, how to run, how to verify, project structure.
  Written for the reviewer: they should run it in under 5 minutes.
- `REQUIREMENTS.md` — assignment text (verbatim) + requirements matrix with status.
- `DECISIONS.md` — one entry per significant decision (ADR-lite format).
- `TROUBLESHOOTING.md` — every real problem I hit: symptom → cause → fix.
- `CLAUDE.md` — this file.

## Commits (I do them — you only suggest)
- At the end of each chunk, suggest: the files to stage + a commit message.
- Small commits. Commit message: plain English, no type prefix (no `feat:`, `fix:`, `docs:`,
  `chore:`, `test:`). Short imperative subject line, e.g. `Add requirements matrix for task 1`.
- One logical change per commit.
- Never `git commit`, `git push`, amend, rebase or force anything yourself.

## My environment
- Windows 11 + WSL2 (Ubuntu) + Docker Desktop. WSL limited to 6GB RAM / 4 CPUs.
- Keep resource usage low; set memory limits on heavy containers.
