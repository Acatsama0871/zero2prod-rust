# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Rust web application built with Actix-Web framework, implementing a newsletter subscription service. The project follows the "Zero to Production in Rust" book patterns.

## Common Development Commands

### Database Setup
```bash
# Initialize PostgreSQL database with Docker and run migrations
./scripts/init_db.sh

# Environment variable needed for database operations
export DATABASE_URL="postgres://app:secret@localhost:5432/newsletter"
```

### Build and Run
```bash
# Build the project
cargo build

# Run in development mode
cargo run

# Build release version
cargo build --release

# Run the application
./target/debug/zero2prod
```

### Testing
```bash
# Run all tests
cargo test

# Run tests with output
cargo test -- --nocapture

# Run specific test
cargo test test_name

# Run tests with logging output
TEST_LOG=true cargo test

# Run integration tests only
cargo test --test '*'
```

### Database Migrations
```bash
# Create new migration
sqlx migrate add <migration_name>

# Run migrations
sqlx migrate run

# Check migration status
sqlx migrate info

# Revert last migration
sqlx migrate revert
```

### Code Quality
```bash
# Check code without building
cargo check

# Format code
cargo fmt

# Run clippy linter
cargo clippy

# Fix clippy warnings
cargo clippy --fix
```

## Architecture and Key Patterns

### Application Structure
The application follows a layered architecture with clear separation of concerns:

1. **Main Entry Point** (`src/main.rs`): Initializes telemetry, loads configuration, and starts the application
2. **Application Bootstrap** (`src/startup.rs`): 
   - `Application` struct manages the server lifecycle
   - Database connection pool setup using `sqlx::PgPool` with lazy connections
   - HTTP server configuration with Actix-Web
3. **Configuration** (`src/configuration.rs`):
   - Hierarchical configuration loading: base.yaml → environment-specific (local/production)
   - Environment variables can override with `APP_` prefix
   - Supports local and production environments via `APP_ENVIRONMENT`

### Domain Modeling
Located in `src/domain/`:
- **Value Objects**: `SubscriberName`, `SubscriberEmail` with validation
- **Entities**: `NewSubscriber` representing domain concepts
- Strong typing and parse-don't-validate pattern

### API Routes
Located in `src/routes/`:
- `/health_check`: Simple health endpoint
- `/subscriptions`: Newsletter subscription endpoint with form validation

### Database Integration
- Uses SQLx for compile-time checked queries
- PostgreSQL with migrations in `migrations/`
- Subscription workflow with status tracking and token-based confirmation

### Testing Strategy
Tests in `tests/api/`:
- **Test Helpers** (`helpers.rs`): 
  - `TestApp` struct for test isolation
  - Automatic database provisioning per test with unique UUIDs
  - MockServer for email client testing
  - Tracing setup controlled by `TEST_LOG` environment variable

### Observability
- Structured logging with `tracing` and `tracing-bunyan-formatter`
- Request tracing with `tracing-actix-web`
- Configurable log levels via subscriber initialization

### External Services
- **Email Client** (`src/email_client.rs`): HTTP-based email service integration with configurable timeout
- Uses `reqwest` for HTTP requests with rustls

### Security Considerations
- Secrets management using `secrecy` crate for passwords and tokens
- SSL/TLS support for database connections
- Input validation at domain boundaries

## Configuration Files

The application uses YAML configuration files:
- `configuration/base.yaml`: Default settings
- `configuration/local.yaml`: Local development overrides  
- `configuration/production.yaml`: Production settings

Configuration can be overridden via environment variables prefixed with `APP_` (e.g., `APP_DATABASE__HOST`).

## Database Schema

Key tables:
- `subscriptions`: Stores subscriber information with status tracking
- `subscription_tokens`: Manages confirmation tokens for double opt-in

## Development Tips

1. Use `./scripts/init_db.sh` to quickly set up a local PostgreSQL instance
2. Run tests with `TEST_LOG=true` to see tracing output during test execution
3. The application supports hot-reloading with `cargo watch -x run`
4. Database queries are compile-time checked - run `cargo sqlx prepare` before committing