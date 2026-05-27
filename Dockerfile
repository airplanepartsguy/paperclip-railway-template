FROM node:20-slim

# Install gosu for privilege dropping + wget/unzip for SDK download + JDK 17 + ffmpeg + Python 3 for Hermes
RUN apt-get update && apt-get install -y --no-install-recommends \
      gosu wget unzip openjdk-17-jdk-headless ffmpeg \
      python3 python3-pip python3-venv \
  && rm -rf /var/lib/apt/lists/*

# Install Hermes Agent (Nous Research) — required by the hermes_local adapter
RUN python3 -m pip install --break-system-packages hermes-agent \
  && hermes --version

# node-mobile toolchain: Android SDK (cmdline-tools 14742923)
# Path A (TUR-254): extend base Railway image in-place for v1.
ARG CMDLINE_TOOLS_VERSION=14742923
ARG BUILD_TOOLS_VERSION=34.0.0

ENV ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_HOME=/opt/android-sdk \
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

RUN mkdir -p "${ANDROID_SDK_ROOT}/cmdline-tools" \
  && wget -q "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip" -O /tmp/cmdline-tools.zip \
  && unzip -q /tmp/cmdline-tools.zip -d /tmp/cmdline-tools-extract \
  && mv /tmp/cmdline-tools-extract/cmdline-tools "${ANDROID_SDK_ROOT}/cmdline-tools/latest" \
  && rm -rf /tmp/cmdline-tools.zip /tmp/cmdline-tools-extract \
  && yes | "${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager" --licenses \
  && "${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager" \
       "platform-tools" \
       "build-tools;${BUILD_TOOLS_VERSION}" \
       "platforms;android-34" \
       "platforms;android-35" \
  && chmod -R 755 "${ANDROID_SDK_ROOT}"

# Build-time smoke — validates toolchain is functional
RUN javac -version \
  && "${ANDROID_SDK_ROOT}/platform-tools/adb" version \
  && ffmpeg -version 2>&1 | head -1 \
  && "${ANDROID_SDK_ROOT}/build-tools/${BUILD_TOOLS_VERSION}/apksigner" version

# Create a non-root user (required: Claude CLI refuses --dangerously-skip-permissions as root)
RUN groupadd -r paperclip && useradd -r -g paperclip -m -d /home/paperclip -s /bin/bash paperclip

# Create the paperclip home directory (Railway volume mount point)
RUN mkdir -p /paperclip && chown -R paperclip:paperclip /paperclip

WORKDIR /app

# Copy package files and install dependencies
COPY package.json ./
RUN npm install --omit=dev

# Copy application code
COPY . .

# Give ownership of everything to the non-root user
RUN chown -R paperclip:paperclip /app /home/paperclip

# Copy and set up entrypoint (fixes volume mount ownership at runtime)
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Railway injects PORT at runtime (default 3100)
ENV PORT=3100 \
    PATH="/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:/opt/android-sdk/build-tools/34.0.0:${PATH}"
EXPOSE 3100

# Entrypoint runs as root to fix volume permissions, then drops to paperclip user
ENTRYPOINT ["/entrypoint.sh"]
CMD ["npm", "start"]
