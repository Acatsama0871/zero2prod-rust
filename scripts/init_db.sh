#!/usr/bin/env bash
set -eo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check and install sqlx-cli
ensure_sqlx_cli() {
    if command_exists sqlx; then
        local version=$(sqlx --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        log_info "sqlx-cli is already installed (version: ${version})"
        return 0
    fi
    
    log_warn "sqlx-cli not found"
    
    # Check if cargo is available
    if ! command_exists cargo; then
        log_error "Cargo is not installed. Please install Rust and Cargo first."
        log_info "Visit https://rustup.rs/ for installation instructions"
        return 1
    fi
    
    log_info "Installing sqlx-cli with cargo..."
    if cargo install --version="~0.8" sqlx-cli \
        --no-default-features \
        --features rustls,postgres; then
        log_info "sqlx-cli installed successfully"
        
        # Verify installation
        if command_exists sqlx; then
            local version=$(sqlx --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
            log_info "sqlx-cli version ${version} is now available"
            return 0
        else
            log_warn "sqlx-cli installed but not found in PATH"
            log_info "You may need to add ~/.cargo/bin to your PATH"
            return 1
        fi
    else
        log_error "Failed to install sqlx-cli"
        return 1
    fi
}

# Function to cleanup existing container
cleanup_existing_container() {
    local container_name=$1
    
    if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        log_warn "Container '${container_name}' already exists"
        
        # Check if container is running
        if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
            log_info "Stopping running container '${container_name}'..."
            docker stop "${container_name}" >/dev/null 2>&1
        fi
        
        log_info "Removing existing container '${container_name}'..."
        docker rm "${container_name}" >/dev/null 2>&1
        log_info "Container '${container_name}' removed successfully"
    fi
}

# Function to wait for PostgreSQL to be ready
wait_for_postgres() {
    local container_name=$1
    local max_attempts=30
    local attempt=0
    
    log_info "Waiting for PostgreSQL to be ready..."
    
    while [ $attempt -lt $max_attempts ]; do
        # Check if container has health check
        if docker inspect "${container_name}" 2>/dev/null | grep -q '"Healthcheck"'; then
            # Use health check if available
            health_status=$(docker inspect -f "{{.State.Health.Status}}" "${container_name}" 2>/dev/null || echo "unknown")
            if [ "$health_status" == "healthy" ]; then
                log_info "PostgreSQL is healthy and ready!"
                return 0
            fi
        else
            # Fallback to checking if postgres is accepting connections
            if docker exec "${container_name}" pg_isready -U "${SUPERUSER}" >/dev/null 2>&1; then
                log_info "PostgreSQL is ready to accept connections!"
                return 0
            fi
        fi
        
        echo -n "."
        sleep 1
        ((attempt++))
    done
    
    echo ""
    log_error "PostgreSQL failed to become ready within ${max_attempts} seconds"
    return 1
}

# Function to run sqlx database operations
run_sqlx_operations() {
    local database_url=$1
    
    log_info "Running sqlx database operations..."
    
    # Export DATABASE_URL for sqlx
    export DATABASE_URL="${database_url}"
    log_debug "DATABASE_URL set to: ${DATABASE_URL}"
    
    # Step 1: Create database
    log_info "Creating database using sqlx..."
    if sqlx database create 2>/dev/null; then
        log_info "Database created successfully (or already exists)"
    else
        # Check if it's just because database already exists
        if sqlx database create 2>&1 | grep -q "already exists"; then
            log_info "Database already exists"
        else
            log_warn "Could not create database with sqlx (may already exist or have permission issues)"
        fi
    fi
    
    # Step 2: Always run migrations (even if migrations directory doesn't exist yet)
    log_info "Running sqlx migrate run..."
    if [ -d "migrations" ]; then
        log_info "Found migrations directory"
        if sqlx migrate run; then
            log_info "✓ Migrations completed successfully"
            
            # Show migration status after running
            log_info "Current migration status:"
            sqlx migrate info || true
        else
            log_error "Failed to run migrations"
            log_info "Attempting to show migration status for debugging:"
            sqlx migrate info || true
            return 1
        fi
    else
        log_warn "No migrations directory found"
        log_info "Creating migrations directory..."
        mkdir -p migrations
        
        # Try to run migrate anyway (will report no migrations to run)
        if sqlx migrate run 2>&1 | tee /tmp/sqlx_output.txt | grep -q "No migrations"; then
            log_info "No migrations to run (migrations directory is empty)"
        else
            cat /tmp/sqlx_output.txt
        fi
        rm -f /tmp/sqlx_output.txt
        
        log_info "Tip: Create your first migration with: sqlx migrate add <migration_name>"
    fi
    
    # Show helpful information about migrations
    echo ""
    log_info "Migration commands available:"
    echo "  sqlx migrate add <name>  - Create a new migration"
    echo "  sqlx migrate run         - Apply pending migrations"
    echo "  sqlx migrate info        - Show migration status"
    echo "  sqlx migrate revert      - Revert last migration"
    echo ""
}

# Parse command line arguments
SKIP_CLEANUP=false
SKIP_SQLX=false
INSTALL_SQLX=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-cleanup)
            SKIP_CLEANUP=true
            shift
            ;;
        --skip-sqlx)
            SKIP_SQLX=true
            shift
            ;;
        --install-sqlx)
            INSTALL_SQLX=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            set -x
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --skip-cleanup    Don't remove existing container (will fail if exists)"
            echo "  --skip-sqlx       Skip sqlx-cli operations"
            echo "  --install-sqlx    Force installation of sqlx-cli even if found"
            echo "  --verbose, -v     Enable verbose output"
            echo "  --help, -h        Show this help message"
            echo ""
            echo "Environment variables:"
            echo "  POSTGRES_PORT     Port to expose PostgreSQL (default: 5432)"
            echo "  POSTGRES_USER     PostgreSQL superuser name (default: postgres)"
            echo "  POSTGRES_PASSWORD PostgreSQL superuser password (default: password)"
            echo "  APP_USER          Application user name (default: app)"
            echo "  APP_USER_PWD      Application user password (default: secret)"
            echo "  APP_DB_NAME       Application database name (default: newsletter)"
            echo "  POSTGRES_VERSION  PostgreSQL Docker image version (default: latest)"
            echo "  DATABASE_URL      Will be exported for sqlx operations"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Configuration with default values
DB_PORT="${POSTGRES_PORT:-5432}"
SUPERUSER="${POSTGRES_USER:-postgres}"
SUPERUSER_PWD="${POSTGRES_PASSWORD:-password}"
APP_USER="${APP_USER:-app}"
APP_USER_PWD="${APP_USER_PWD:-secret}"
APP_DB_NAME="${APP_DB_NAME:-newsletter}"
POSTGRES_VERSION="${POSTGRES_VERSION:-latest}"
CONTAINER_NAME="${CONTAINER_NAME:-postgres}"

# Build DATABASE_URL
DATABASE_URL="postgres://${APP_USER}:${APP_USER_PWD}@localhost:${DB_PORT}/${APP_DB_NAME}"

# Display configuration
log_info "PostgreSQL Docker Setup Configuration:"
echo "  Container Name:     ${CONTAINER_NAME}"
echo "  PostgreSQL Version: ${POSTGRES_VERSION}"
echo "  Database Port:      ${DB_PORT}"
echo "  Superuser:          ${SUPERUSER}"
echo "  App User:           ${APP_USER}"
echo "  App Database:       ${APP_DB_NAME}"
echo "  Skip sqlx:          ${SKIP_SQLX}"
echo ""

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    log_error "Docker is not running or not installed"
    exit 1
fi

# Check and install sqlx-cli if needed and not skipped
if [ "$SKIP_SQLX" = false ]; then
    if [ "$INSTALL_SQLX" = true ]; then
        # Force reinstall
        log_info "Force installing sqlx-cli..."
        cargo uninstall sqlx-cli 2>/dev/null || true
        if ! ensure_sqlx_cli; then
            log_warn "Failed to install sqlx-cli. Continuing without it..."
            SKIP_SQLX=true
        fi
    else
        # Check and install if needed
        if ! ensure_sqlx_cli; then
            log_warn "sqlx-cli not available. Continuing without it..."
            SKIP_SQLX=true
        fi
    fi
fi

# Clean up existing container if not skipped
if [ "$SKIP_CLEANUP" = false ]; then
    cleanup_existing_container "${CONTAINER_NAME}"
fi

# Pull the PostgreSQL image
log_info "Pulling PostgreSQL image (postgres:${POSTGRES_VERSION})..."
docker pull "postgres:${POSTGRES_VERSION}" || {
    log_error "Failed to pull PostgreSQL image"
    exit 1
}

# Launch PostgreSQL container
log_info "Starting PostgreSQL container '${CONTAINER_NAME}'..."
CONTAINER_ID=$(docker run \
    --env POSTGRES_USER="${SUPERUSER}" \
    --env POSTGRES_PASSWORD="${SUPERUSER_PWD}" \
    --env POSTGRES_DB="${APP_DB_NAME}" \
    --publish "${DB_PORT}:5432" \
    --detach \
    --name "${CONTAINER_NAME}" \
    --health-cmd="pg_isready -U ${SUPERUSER}" \
    --health-interval=5s \
    --health-timeout=5s \
    --health-retries=5 \
    "postgres:${POSTGRES_VERSION}" \
    -N 1000)

if [ -z "$CONTAINER_ID" ]; then
    log_error "Failed to start PostgreSQL container"
    exit 1
fi

log_info "Container started with ID: ${CONTAINER_ID:0:12}"

# Wait for PostgreSQL to be ready
if ! wait_for_postgres "${CONTAINER_NAME}"; then
    log_error "PostgreSQL startup failed. Checking container logs..."
    docker logs --tail 20 "${CONTAINER_NAME}"
    exit 1
fi

# Create the application user if it doesn't exist
log_info "Creating application user '${APP_USER}'..."
CREATE_USER_QUERY="DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_user WHERE usename = '${APP_USER}') THEN
        CREATE USER ${APP_USER} WITH PASSWORD '${APP_USER_PWD}';
    ELSE
        ALTER USER ${APP_USER} WITH PASSWORD '${APP_USER_PWD}';
    END IF;
END
\$\$;"

if docker exec "${CONTAINER_NAME}" psql -U "${SUPERUSER}" -d "${APP_DB_NAME}" -c "${CREATE_USER_QUERY}"; then
    log_info "Application user '${APP_USER}' created/updated successfully"
else
    log_error "Failed to create application user"
    exit 1
fi

# Grant privileges to the application user
log_info "Granting privileges to application user..."
GRANT_QUERY="ALTER USER ${APP_USER} CREATEDB;
GRANT ALL PRIVILEGES ON DATABASE ${APP_DB_NAME} TO ${APP_USER};
GRANT ALL ON SCHEMA public TO ${APP_USER};"

if docker exec "${CONTAINER_NAME}" psql -U "${SUPERUSER}" -d "${APP_DB_NAME}" -c "${GRANT_QUERY}"; then
    log_info "Privileges granted successfully"
else
    log_error "Failed to grant privileges"
    exit 1
fi

# Export DATABASE_URL for other tools
export DATABASE_URL="${DATABASE_URL}"
log_info "DATABASE_URL exported: ${DATABASE_URL}"

# Run sqlx operations if not skipped
if [ "$SKIP_SQLX" = false ] && command_exists sqlx; then
    run_sqlx_operations "${DATABASE_URL}"
else
    if [ "$SKIP_SQLX" = true ]; then
        log_info "Skipping sqlx operations (--skip-sqlx flag set)"
    else
        log_info "Skipping sqlx operations (sqlx-cli not available)"
    fi
fi

# Display connection information
echo ""
log_info "PostgreSQL is up and running!"
echo ""
echo "Connection Details:"
echo "  Host:     localhost"
echo "  Port:     ${DB_PORT}"
echo "  Database: ${APP_DB_NAME}"
echo ""
echo "Superuser Connection:"
echo "  psql -h localhost -p ${DB_PORT} -U ${SUPERUSER} -d ${APP_DB_NAME}"
echo ""
echo "Application User Connection:"
echo "  psql -h localhost -p ${DB_PORT} -U ${APP_USER} -d ${APP_DB_NAME}"
echo ""
echo "Connection String:"
echo "  ${DATABASE_URL}"
echo ""
echo "Environment Variable:"
echo "  export DATABASE_URL=\"${DATABASE_URL}\""
echo ""

# Write connection info to .env file if it exists or create one
if [ -f ".env" ]; then
    # Check if DATABASE_URL already exists in .env
    if grep -q "^DATABASE_URL=" .env; then
        log_info "Updating DATABASE_URL in .env file..."
        # Use a temp file for safer replacement
        grep -v "^DATABASE_URL=" .env > .env.tmp
        echo "DATABASE_URL=${DATABASE_URL}" >> .env.tmp
        mv .env.tmp .env
    else
        log_info "Adding DATABASE_URL to .env file..."
        echo "DATABASE_URL=${DATABASE_URL}" >> .env
    fi
else
    log_info "Creating .env file with DATABASE_URL..."
    echo "DATABASE_URL=${DATABASE_URL}" > .env
fi

log_info "Setup completed successfully!"