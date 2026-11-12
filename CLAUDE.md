# CLAUDE.md

Home assignment for a DevOps Engineer position: three independent tasks in one repository.
All three are finished and verified. See [README.md](README.md) for the overview.

## Layout

| Folder                | Task                                                      | Entry point                                   |
|-----------------------|-----------------------------------------------------------|-----------------------------------------------|
| `1-jenkins-pipeline/` | Jenkins pipeline + Groovy shared library (`prepareEnv`)   | `Jenkinsfile`, `shared-library/vars/prepareEnv.groovy`, `docker-compose.yml` |
| `2-ansible-docker/`   | Ansible playbook that deploys a Docker Compose app        | `playbook.yml`, `templates/compose.yaml.j2`   |
| `3-bash-extract/`     | Bash script that unpacks archives by content type         | `extract`, `tests/*.bats`                     |

Every task folder has the same documents. Keep them in sync with the code:

- `README.md` — what it is, prerequisites, how to run, how to verify.
- `REQUIREMENTS.md` — assignment text (verbatim, never edit it) + requirements matrix.
- `DECISIONS.md` — one entry per significant decision (`D-001`, ...).
- `TROUBLESHOOTING.md` — real problems: symptom → cause → fix (`T-001`, ...).

IDs are `R-1` (from the task text), `N-1` (derived), `D-001`, `T-001`.

## Commands

Task 1 — run from `1-jenkins-pipeline/` (needs `.env` and `secrets/`, see its README):

```bash
docker compose up -d --build && ./nexus/setup.sh   # start + configure Nexus
shellcheck nexus/setup.sh
docker run --rm -i hadolint/hadolint:v2.12.0 < jenkins/Dockerfile
docker run --rm -i hadolint/hadolint:v2.12.0 < smee/Dockerfile
```

Task 2 — run from `2-ansible-docker/` with its venv active:

```bash
ansible-playbook playbook.yml                       # deploy + self-check
ansible-lint playbook.yml                           # needs requirements-dev.txt
```

Task 3 — run from `3-bash-extract/`:

```bash
bats tests                                          # all tests must pass
shellcheck -x extract tests/*.bats tests/test_helper.bash
```

## Rules

- Everything in the repo is in English.
- No secrets in git: values live in a git-ignored `.env` (`.env.example` is committed) or in
  `1-jenkins-pipeline/secrets/`. Never print secret values.
- Pin every version (images, plugins, packages, collections). No `latest`.
- Least privilege: non-root containers, ports bound to `127.0.0.1`, minimal permissions.
- Shell: quote variables, `set -euo pipefail` where it fits, pass `shellcheck` / `hadolint` /
  `ansible-lint`.
- Jenkins: SCM data is untrusted — pass it as env vars and use single-quoted `sh '...'`.
- Do not add features the assignment does not ask for; record any interpretation in the task's
  `DECISIONS.md`.
- Comments explain *why*, not what the syntax does.
- Commit messages: plain English, short imperative subject, no type prefix (`feat:`, `fix:` ...).
