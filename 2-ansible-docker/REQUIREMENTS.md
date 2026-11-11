# Requirements — Task 2: Ansible and Docker

## Assignment text (verbatim)

> Ansible and Docker
> Create an ansible playbook that will deploy a docker-compose application containing two
> services:
> 1. Web server that will offer a basic "Hello World" HTML page.
> 2. Stateful service that will keep a counter-hit from the web server in a separate DB
> container.

## Requirements matrix

Rows `R-*` come directly from the assignment text.
Rows `N-*` are derived (reviewer experience, working rules in `CLAUDE.md`); they are not part
of the assignment text. Each `N-*` row was explicitly approved during planning.

| ID  | Requirement | Implementation | Decision | How to verify | Status |
|-----|-------------|----------------|----------|---------------|--------|
| R-1 | Create an Ansible playbook that deploys the application | `playbook.yml`, run on `localhost`, files copied to `~/hello-counter` | D-005, D-008, D-013 | `ansible-playbook playbook.yml` ends with `failed=0` | Planned |
| R-2 | The application is a docker-compose application | `templates/compose.yaml.j2`, deployed with `community.docker.docker_compose_v2` | D-007, D-008 | `docker compose ps` in `~/hello-counter` | Planned |
| R-3 | Two services: a web server and a stateful service | Compose services `web` and `counter` (plus the `redis` DB container, see R-6) | D-001 | `docker compose config --services` | Planned |
| R-4 | Web server offers a basic "Hello World" HTML page | `app/web/app.py` (Flask + gunicorn), page also shows the hit count | D-001, D-002, D-003 | `curl http://localhost:8080` returns `Hello World` | Planned |
| R-5 | Stateful service keeps a hit counter from the web server | `app/counter/app.py`: `POST /hit` → Redis `INCR`; `web` calls it on every page request | D-001, D-003 | Each request increases the count by 1 (second response shows n+1) | Planned |
| R-6 | The counter is stored in a separate DB container | Compose service `redis`, AOF + RDB on a named volume | D-001, D-004 | `docker compose ps` shows 3 containers; count survives `down` + `up` | Planned |
| N-1 | Reviewer runs it with one command (after one-time setup) | `ansible.cfg` + pinned venv + README | D-011, D-012 | Fresh clone → README steps work in < 5 minutes | In progress |
| N-2 | Idempotent: a second run reports no changes | `docker_compose_v2` module, `build: always` relies on the build cache | D-007, D-008 | Second run: `changed=0` (the self-check still adds 2 hits, see D-008) | Planned |
| N-3 | Playbook verifies the deployment itself | `wait: true` on the compose task, then `uri` + `assert` tasks | D-008 | Playbook output shows the count increased | Planned |
| N-4 | Docker is a prerequisite and is checked, not installed | Pre-flight `docker info` task; the module itself enforces Compose >= 2.18 | D-006 | Stop Docker Desktop → playbook fails with a clear message | Planned |
| N-5 | Security: pinned versions, non-root containers, only the web port published, no secrets in the repo | Dockerfiles, compose template, two networks (`backend` is internal) | D-009, D-010 | `hadolint`, `docker compose exec web id`, `docker compose ps` ports | Planned |
| N-6 | Independent of tasks 1 and 3 (no Jenkins, no Nexus) | Images are built on the target by Compose | D-008 | No references to other task folders | Planned |

## Interpretations

The ambiguous parts of the task text and the chosen interpretation are recorded in
[DECISIONS.md — D-001](DECISIONS.md#d-001-interpretation-of-two-services--three-containers).
