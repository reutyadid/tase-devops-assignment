# Jenkins controller: official LTS image + pinned plugins + JCasC config (D-007).
FROM jenkins/jenkins:2.580.2-lts-jdk21

# Plugins are installed at build time, so the controller starts with exactly this set.
# Not in /usr/share/jenkins/ref/: everything there is copied into JENKINS_HOME on every start.
COPY plugins.txt /usr/share/jenkins/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/plugins.txt

# Jenkins configuration as code. Kept outside JENKINS_HOME (a volume),
# so a rebuilt image always applies the config from git.
COPY casc.yaml /usr/share/jenkins/casc.yaml
ENV CASC_JENKINS_CONFIG=/usr/share/jenkins/casc.yaml
