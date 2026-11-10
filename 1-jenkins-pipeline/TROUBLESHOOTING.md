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
