FROM node:24-bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates libfontconfig1 libasound2 libx11-6 libxcursor1 libxinerama1 \
    libxrandr2 libxi6 libgl1 && rm -rf /var/lib/apt/lists/*
WORKDIR /opt/battlebots
COPY services/matchmaking/ ./service/
COPY battlebots/exports/hosted-server/ ./game/
RUN chmod 755 ./game/battlebots-server.x86_64
ENV NODE_ENV=production HOST=0.0.0.0 PORT=8080 \
    GODOT_PATH=/opt/battlebots/game/battlebots-server.x86_64 \
    BUILD_MANIFEST_PATH=/opt/battlebots/game/manifest.json \
    STATE_DIRECTORY=/tmp/battlebots-matchmaking \
    BIND_ADDRESS=fly-global-services
USER node
EXPOSE 8080/tcp 24570/udp 24571/udp 24572/udp 24573/udp
CMD ["node", "service/index.mjs"]
