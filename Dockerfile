# ========================================================
# Lodestone Production Dockerfile
# Combines Node.js 22 LTS runtime with Python 3.12 Archipelago Core
# ========================================================

FROM python:3.12-slim-bookworm

# Set work directory
WORKDIR /app/backend

# Prevent Python from writing pyc files and buffering stdout/stderr
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PYTHON=python3
ENV NODE_ENV=development
ENV PORT=8080
ENV AP_START_PORT=38000
ENV AP_MAX_PORT=38010

# Install required system packages and dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    build-essential \
    python3-dev \
    python-is-python3 \
    net-tools \
    sqlite3 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 22 LTS
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs && \
    npm install -g npm@latest && \
    rm -rf /var/lib/apt/lists/*

# Download the runtime dependency that is intentionally not stored in Git.
RUN git clone --depth 1 https://github.com/ArchipelagoMW/Archipelago.git /opt/archipelago_core

# Copy backend package manifests and install npm dependencies
COPY backend/package*.json ./
RUN npm install --include=dev && cd node_modules/better-sqlite3 && npx --yes node-gyp rebuild && cd ../..

# Install Archipelago Python dependencies
RUN pip install --no-cache-dir \
    -r /opt/archipelago_core/requirements.txt

# Copy backend source code and assets
COPY backend/src ./src
COPY backend/public ./public
COPY backend/data ./data
COPY backend/tsconfig.json ./tsconfig.json
RUN rm -rf archipelago_core && mv /opt/archipelago_core ./archipelago_core


# Build TypeScript to JavaScript
RUN npm run build

# Create persistent storage directories
RUN mkdir -p temp_seeds failed_generations updates public/admin

# Expose Lodestone Lobby HTTP/WS and Central MultiServer port range
EXPOSE 8080
EXPOSE 38000-38010

# Launch Lodestone Backend Server
CMD ["node", "dist/index.js"]
