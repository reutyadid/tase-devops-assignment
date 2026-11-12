# DevOps Engineer home assignment

Three independent tasks, each in its own folder with its own README, requirements matrix,
design decisions and troubleshooting notes. Every task runs locally and was verified end to end.

| # | Task | What it does | Main tools |
|---|------|--------------|------------|
| 1 | [Jenkins pipeline](1-jenkins-pipeline/) | A push to GitHub triggers a pipeline that builds, packs and uploads a Java app to Nexus. A Groovy shared-library function, `prepareEnv`, passes the SCM trigger parameters (committer, commit, branch, ...) into the pipeline. | Jenkins (JCasC, Job DSL), Groovy, Maven, Nexus, Docker Compose |
| 2 | [Ansible and Docker](2-ansible-docker/) | An Ansible playbook deploys a Docker Compose app: a web server with a "Hello World" page and a stateful counter service that stores the hit count in a separate Redis container. | Ansible, Docker Compose, Python (Flask), Redis |
| 3 | [Bash `extract`](3-bash-extract/) | A Bash script that unpacks gzip, bzip2, zip and compress files, chosen only by the `file` command, with `-h`, `-r` and `-v`. | Bash, `file`, bats, ShellCheck |

## Tested environment

Windows 11 + WSL2 (Ubuntu 24.04), Docker Desktop (Docker 29.9.3, Compose v5.7.0), Bash 5.2,
Python 3.12.

## How to run each task

Clone the repository into the Linux file system (for example `~/`), then follow the task README.
In short:

**Task 1 — Jenkins pipeline** ([full steps](1-jenkins-pipeline/README.md#quick-start)).
Needs a public fork (Jenkins reads the Jenkinsfile and the library from it) and a smee.io
channel for the GitHub webhook.

```bash
cd 1-jenkins-pipeline
cp .env.example .env               # then fill it in (README steps 1-3: passwords, SSH key, webhook)
docker compose up -d --build
./nexus/setup.sh
# push a commit to main → Jenkins at http://localhost:8080 builds, packs and uploads to Nexus
```

**Task 2 — Ansible and Docker** ([full steps](2-ansible-docker/README.md#quick-start)).

```bash
cd 2-ansible-docker
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
ansible-galaxy collection install -r requirements.yml
ansible-playbook playbook.yml
curl -s localhost:8080             # Hello World + page views
```

**Task 3 — Bash `extract`** ([full steps](3-bash-extract/README.md#quick-start)).

```bash
cd 3-bash-extract
./extract -v path/to/archive_or_folder
bats tests                         # the test suite
```

## Repository layout

```
.
├── 1-jenkins-pipeline/   # task 1
├── 2-ansible-docker/     # task 2
├── 3-bash-extract/       # task 3
├── CLAUDE.md             # project guide for Claude Code (AI assistant used during development)
└── .claude/settings.json # shared Claude Code settings (blocks reading secret files)
```

Each task folder contains:

- `README.md` — prerequisites, quick start, how to verify, project structure.
- `REQUIREMENTS.md` — the assignment text (verbatim) and a requirements matrix: every
  requirement, where it is implemented, how it was verified, and its status.
- `DECISIONS.md` — design decisions with the options considered and sources.
- `TROUBLESHOOTING.md` — real problems met during development, with cause and fix.
