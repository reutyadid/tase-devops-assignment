# smee.io client: receives the GitHub webhook from the public smee.io channel and forwards it to
# Jenkins inside the Compose network, so Jenkins needs no inbound port from the internet (D-002).
FROM node:24.22-alpine3.24

RUN npm install --global smee-client@5.0.0 && npm cache clean --force

USER node
# Channel URL and token are read from Docker secret files at start, so they are not in the
# container config (`docker inspect`). SMEE_TARGET is the Jenkins endpoint, not a secret.
ENTRYPOINT ["/bin/sh", "-c", "exec smee --url \"$(cat /run/secrets/smee_url)\" --target \"$SMEE_TARGET?token=$(cat /run/secrets/gwt_token)\""]
