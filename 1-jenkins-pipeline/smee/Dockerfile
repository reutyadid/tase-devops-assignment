# smee.io client: receives the GitHub webhook from the public smee.io channel and forwards it to
# Jenkins inside the Compose network, so Jenkins needs no inbound port from the internet (D-002).
FROM node:24.22-alpine3.24

RUN npm install --global smee-client@5.0.0 && npm cache clean --force

USER node
ENTRYPOINT ["smee"]
