# Linux Swift toolchain for validating the platform-independent domain layer.
# The SwiftUI + SwiftData app itself is built on macOS with Xcode; this image
# only compiles and tests `Climbing/Domain` via the root SwiftPM package.
FROM swift:6.0.3

RUN apt-get update \
    && apt-get install -y --no-install-recommends git curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*
