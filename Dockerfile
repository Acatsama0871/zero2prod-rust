# Compute a lock-like file for our project
FROM lukemathwalker/cargo-chef:latest-rust-1.89.0 AS chef
WORKDIR /app
RUN apt update && apt install lld clang -y
FROM chef AS planner
COPY . .
RUN cargo chef prepare --recipe-path recipe.json

# Build our project dependencies, not our application!
FROM chef AS builder
COPY --from=planner /app/recipe.json recipe.json
RUN cargo chef cook --release --recipe-path recipe.json
# Up to this point, if our dependency tree stays the same,
# all layers should be cached.
COPY . .
ENV SQLX_OFFLINE=true
# Build our project
RUN cargo build --release --bin zero2prod

# build runtime
FROM debian:bookworm-slim AS runtime
WORKDIR /app
RUN apt-get update -y \
    && apt-get install -y --no-install-recommends openssl ca-certificates \
    # Clean up
    && apt-get autoremove -y \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/target/release/zero2prod zero2pro
