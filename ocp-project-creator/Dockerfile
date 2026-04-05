FROM quay.io/openshift/origin-cli:latest

RUN dnf install -y nodejs npm && dnf clean all

WORKDIR /app

COPY package*.json ./
RUN npm install --production

COPY server.js ./
COPY public/ ./public/

EXPOSE 8080

USER 1001

CMD ["node", "server.js"]
