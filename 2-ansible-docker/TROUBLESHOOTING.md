# Troubleshooting

Real problems I hit while building this, and how I solved them.

---

## T-001: `error getting credentials` on the first build (WSL + Docker Desktop)

- **Symptom:** The first `docker compose up --build` (the playbook's deploy task runs the
  same thing) failed while pulling the base image:
  ```
  error getting credentials - err: exit status 1
  ```
  The WSL log also showed `UtilAcceptVsock ... accept4 failed 110` (a timeout).
- **Root cause:** `~/.docker/config.json` in WSL has `"credsStore": "desktop.exe"`. Docker
  calls the Windows credential helper through WSL interop to look up registry credentials,
  even for public images. That call timed out. It is a WSL / Docker Desktop issue, not a
  problem in this project.
- **Fix:** It was transient. Running the same command again worked. If it keeps failing:
  1. Restart WSL and Docker Desktop: in PowerShell run `wsl --shutdown`, then start
     Docker Desktop again.
  2. If you do not log in to any registry from WSL: back up `~/.docker/config.json` and
     remove the `"credsStore": "desktop.exe"` line. Public images are pulled without
     credentials.
- **How to verify:** `docker pull python:3.12.16-slim-trixie` succeeds.
- **Lesson:** On WSL with Docker Desktop, a failed pull of a public image can be a local
  credential-helper problem, not a network or registry problem. Retry first.

---

## T-002: Playbook hangs at "Check that the Docker daemon is reachable"

- **Symptom:** With Docker Desktop stopped, the playbook stayed on this task for minutes
  instead of failing with the pre-flight message:
  ```
  TASK [Check that the Docker daemon is reachable] ****
  ```
- **Root cause:** In WSL with Docker Desktop stopped, `docker info` does not fail. It waits
  for the daemon with no time limit, so the next task (the clear error message) never ran.
- **Fix:** The task runs `timeout -k 5 20 docker info` (`playbook.yml`; 20 is the variable
  `docker_check_timeout` in `group_vars/all.yml`). After 20 seconds
  `timeout` stops the command with exit code 124, and the playbook fails with the message
  "Docker is not reachable ... Exit code 124 (124 = no answer within 20s)" (D-006).
  If you see this message: start Docker Desktop, wait until it shows "Engine running", and run
  the playbook again.
- **How to verify:** Stop Docker Desktop and run `ansible-playbook playbook.yml`. It fails
  after about 20 seconds with `failed=1` and the message above.
- **Lesson:** A pre-flight check must have its own timeout, or it can hang instead of failing.
