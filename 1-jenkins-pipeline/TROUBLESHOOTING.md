# Troubleshooting

Real problems I hit while building this, and how I solved them.

---

## T-001: Maven Wrapper checksum fails although the download is valid

- **Symptom:** `./mvnw verify` on the agent image stopped right after downloading Maven.
  ```
  Error: Failed to validate Maven distribution SHA-256, your Maven distribution might be compromised.
  ```
- **Root cause:** The wrapper was generated with the default type `only-script`. In that type
  the shell script downloads `apache-maven-3.10.0-bin.zip` when `unzip` is installed, and the
  `.tar.gz` when it is not. The agent image has no `unzip`, so it downloaded the `.tar.gz`, while
  `distributionSha256Sum` held the checksum of the `.zip`. (`mvnw.cmd` on Windows always uses the
  zip, so this is specific to `only-script` on machines without `unzip`.)
- **What did not work:** type `script` — it downloads the wrapper jar with `curl`/`wget`, and the
  agent image has neither:
  ```
  Error: Could not find or load main class org.apache.maven.wrapper.MavenWrapperMain
  ```
- **Fix:** Regenerated the wrapper with type `source` (D-008). A committed
  `MavenWrapperDownloader.java` fetches the wrapper jar with plain Java; the jar then downloads
  and unpacks the zip itself. Same file everywhere, so both `wrapperSha256Sum` and
  `distributionSha256Sum` work. Checksums were computed after verifying the files against the
  hashes published by Apache / Maven Central.
- **How to verify:** run the build on the real agent image (no Java/Maven needed on the host):
  ```bash
  cd 1-jenkins-pipeline/app
  docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD:/app" -w /app \
    --entrypoint ./mvnw jenkins/ssh-agent:9.3.2-jdk21 -B verify
  # expected: Tests run: 1, Failures: 0 ... BUILD SUCCESS
  ```
  Negative check: with a wrong `distributionSha256Sum` the wrapper stops with
  `Failed to validate Maven distribution SHA-256`.
- **Lesson:** Read the wrapper script before adding a checksum; test on the same image that CI uses.

---

## T-002: Upload to Nexus returns 403 although the user is admin

- **Symptom:** a test upload to `maven-releases` with the admin user failed:
  ```
  HTTP 403
  You must accept the End User License Agreement (EULA) through the onboarding wizard or REST API before proceeding.
  ```
- **Root cause:** Nexus Community Edition (3.98.1) blocks uploads until the EULA is accepted. It is
  not a permissions problem. The healthcheck does not show it: `/service/rest/v1/status/writable`
  returns 200 even while the EULA is not accepted.
- **Fix:** accept the EULA once, through the UI or `POST /service/rest/v1/system/eula`. It is never
  accepted on the reviewer's behalf: the setup script (chunk C4) does it only if `.env` has
  `NEXUS_ACCEPT_EULA=true` (D-012).
- **How to verify:**
  ```bash
  curl -s -u "admin:<password>" http://localhost:8081/service/rest/v1/system/eula
  # expected after acceptance: "accepted" : true
  ```
- **Lesson:** "healthy" means the server is up, not that it is ready for our use case; test the
  real action (an upload) early.

---

## T-003: `curl: option -K: error encountered when reading a file`

- **Symptom:** every API call in `nexus/setup.sh` failed with exit code 26:
  ```
  curl: option -K: error encountered when reading a file
  ```
- **Root cause:** the credentials were passed as `-K <(printf ...)` inside an array assignment
  (`local args=(... -K <(...))`), and curl ran on a later line. Bash closes the file that `<(...)`
  creates as soon as the command that created it ends, so curl got the name of a file that no
  longer existed.
- **Fix:** put `-K <(printf ...)` directly on the `curl` line.
- **How to verify:** `./nexus/setup.sh` prints `Admin password changed.` (or `already set.`).
- **Lesson:** a process substitution lives only for the command it is written in.

---

## T-004: Deploy user gets 403 on its first upload

- **Symptom:** a role with `nx-repository-view-maven2-maven-releases-read` and `-add` was not enough.
  An upload of a new file to `maven-releases` as the deploy user returned `403` with no body.
- **Root cause:** Nexus checks the `edit` action as well when a file is written, also for a new path.
- **Fix:** added `nx-repository-view-maven2-maven-releases-edit` to the role (D-011).
- **How to verify:** upload a new file to `maven-releases` as the deploy user → `201`; the same
  file again → `409` (release repository: no redeploy); upload to `maven-snapshots` → `403`.
- **Lesson:** start from the smallest privilege set and test it with the real action.

---

## T-005: `source .env` fails on the SSH public key

- **Symptom:** after adding the agent public key to `.env`, reading the file with bash failed:
  ```
  .env: line 15: AAAAC3NzaC1lZDI1NTE5...: No such file or directory
  ```
  `nexus/setup.sh` reads `.env` the same way, so it would fail too.
- **Root cause:** the key has spaces (`ssh-ed25519 AAAA... jenkins-agent`). Unquoted, bash reads
  `JENKINS_AGENT_SSH_PUBKEY=ssh-ed25519` as a variable for the next word, and runs the next word
  as a command. Docker Compose reads the same line fine, so `docker compose up` worked.
- **Fix:** keep the value in double quotes. Both bash and Compose remove the quotes:
  ```
  JENKINS_AGENT_SSH_PUBKEY="ssh-ed25519 AAAA... jenkins-agent"
  ```
  The command in `.env.example` writes it with quotes.
- **How to verify:** `bash -c 'set -a; source .env; echo ok'` prints `ok`.
- **Lesson:** a `.env` file read by two tools must use syntax both understand.
