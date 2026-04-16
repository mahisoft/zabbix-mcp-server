#!/usr/bin/env bash
# Build a standalone binary of Zabbix MCP Server using PyInstaller.
#
# Usage:
#   ./scripts/build_standalone.sh            # --onedir mode (default, faster startup)
#   ./scripts/build_standalone.sh --onefile   # single-file executable
#
# Requirements: Python 3.10+ and uv (on the build host only).
# The produced binary has no runtime dependencies.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Platform detection ---
OS_RAW="$(uname -s)"
ARCH_RAW="$(uname -m)"

case "$OS_RAW" in
    Linux*)  OS="linux" ;;
    Darwin*) OS="darwin" ;;
    *)       echo "Error: Unsupported OS: $OS_RAW"; exit 1 ;;
esac

case "$ARCH_RAW" in
    x86_64)  ARCH="x86_64" ;;
    aarch64) ARCH="arm64" ;;
    arm64)   ARCH="arm64" ;;
    *)       echo "Error: Unsupported architecture: $ARCH_RAW"; exit 1 ;;
esac

BINARY_NAME="zabbix-mcp-server-${OS}-${ARCH}"

# --- Parse flags ---
MODE="onedir"
for arg in "$@"; do
    case "$arg" in
        --onefile) MODE="onefile" ;;
        --help|-h)
            echo "Usage: $0 [--onefile]"
            echo ""
            echo "Options:"
            echo "  --onefile   Build a single-file executable (slower startup)"
            echo "              Default is --onedir (faster startup, directory output)"
            exit 0
            ;;
        *) echo "Unknown flag: $arg"; exit 1 ;;
    esac
done

echo "=============================================="
echo "Zabbix MCP Server — Standalone Build"
echo "=============================================="
echo "Platform:  ${OS} / ${ARCH}"
echo "Mode:      ${MODE}"
echo "Output:    dist/${BINARY_NAME}"
echo "=============================================="
echo ""

# --- Ensure dev dependencies (includes pyinstaller) ---
echo "Installing dependencies (including PyInstaller)..."
cd "$PROJECT_DIR"
uv sync --group dev --quiet

# --- Clean previous build artifacts ---
rm -rf "$PROJECT_DIR/build/zabbix-mcp-server"
rm -rf "$PROJECT_DIR/dist/zabbix-mcp-server"
rm -rf "$PROJECT_DIR/dist/${BINARY_NAME}"
rm -rf "$PROJECT_DIR/dist/${BINARY_NAME}.dir"

# --- Build ---
echo "Building standalone binary..."

# --- Generate README-bare-metal.md ---
generate_readme() {
    local OUTPUT_DIR="$1"
    cat > "$OUTPUT_DIR/README-bare-metal.md" << 'READMEEOF'
# Zabbix MCP Server — Bare-Metal Install

## Quick Start

1. Copy `.env.example` to `.env` and edit with your Zabbix credentials:

       cp .env.example .env

2. Required settings in `.env`:
   - `ZABBIX_URL` — your Zabbix server URL (e.g., `https://zabbix.example.com`)
   - `ZABBIX_TOKEN` — a Zabbix API token (recommended), OR
   - `ZABBIX_USER` + `ZABBIX_PASSWORD` — username/password auth

3. Run the server:

       ./zabbix-mcp-server-*

## Transport Modes

**stdio (default):** For MCP clients like Claude Desktop that manage the server process.
Set `ZABBIX_MCP_TRANSPORT=stdio` (or omit — it's the default).

**streamable-http:** For network-accessible deployments.
Set in `.env`:

    ZABBIX_MCP_TRANSPORT=streamable-http
    ZABBIX_MCP_HOST=0.0.0.0
    ZABBIX_MCP_PORT=8000
    AUTH_TYPE=zabbix-api-key

## Configuration Reference

See `.env.example` for all available settings including read-only mode,
SSL verification, and debug logging.

## Troubleshooting

**"Missing required environment variables"** — `.env` file not found or missing
`ZABBIX_URL`. Ensure `.env` is in the same directory as the binary.

**"Permission denied"** — Run `chmod +x ./zabbix-mcp-server-*`.

**macOS Gatekeeper warning** — If downloaded from the internet, run:

    xattr -d com.apple.quarantine ./zabbix-mcp-server-*

**"GLIBC_X.Y not found" (Linux)** — The binary was built on a newer Linux
than your host. Rebuild on a host with an older glibc, or use Docker.
READMEEOF
}

# Both modes use the spec file. The spec reads BUILD_ONEFILE to decide
# between onefile (single binary) and onedir (directory with _internal/).
if [ "$MODE" = "onefile" ]; then
    export BUILD_ONEFILE=1
else
    export BUILD_ONEFILE=0
fi

uv run pyinstaller --noconfirm --clean "$SCRIPT_DIR/build_standalone.spec"

if [ "$MODE" = "onefile" ]; then
    # Rename the binary with platform suffix
    mv "$PROJECT_DIR/dist/zabbix-mcp-server" "$PROJECT_DIR/dist/${BINARY_NAME}"

    # Copy support files alongside the binary
    cp "$PROJECT_DIR/config/.env.example" "$PROJECT_DIR/dist/.env.example"
    generate_readme "$PROJECT_DIR/dist"

    BINARY_PATH="$PROJECT_DIR/dist/${BINARY_NAME}"
    BINARY_SIZE=$(du -sh "$BINARY_PATH" | cut -f1)

    echo ""
    echo "=============================================="
    echo "Build complete (onefile)"
    echo "=============================================="
    echo "Binary:  dist/${BINARY_NAME}  (${BINARY_SIZE})"
    echo "Config:  dist/.env.example"
    echo ""
    echo "To run:"
    echo "  cd dist"
    echo "  cp .env.example .env    # edit with your Zabbix credentials"
    echo "  ./${BINARY_NAME}"
    echo "=============================================="

else
    # Rename the output directory with platform suffix
    mv "$PROJECT_DIR/dist/zabbix-mcp-server" "$PROJECT_DIR/dist/${BINARY_NAME}"

    # Rename the binary inside the directory too
    mv "$PROJECT_DIR/dist/${BINARY_NAME}/zabbix-mcp-server" \
       "$PROJECT_DIR/dist/${BINARY_NAME}/${BINARY_NAME}"

    # Copy support files into the output directory
    cp "$PROJECT_DIR/config/.env.example" "$PROJECT_DIR/dist/${BINARY_NAME}/.env.example"
    generate_readme "$PROJECT_DIR/dist/${BINARY_NAME}"

    BINARY_PATH="$PROJECT_DIR/dist/${BINARY_NAME}/${BINARY_NAME}"
    BINARY_SIZE=$(du -sh "$BINARY_PATH" | cut -f1)
    DIR_SIZE=$(du -sh "$PROJECT_DIR/dist/${BINARY_NAME}" | cut -f1)

    echo ""
    echo "=============================================="
    echo "Build complete (onedir)"
    echo "=============================================="
    echo "Directory: dist/${BINARY_NAME}/  (${DIR_SIZE} total)"
    echo "Binary:    dist/${BINARY_NAME}/${BINARY_NAME}  (${BINARY_SIZE})"
    echo "Config:    dist/${BINARY_NAME}/.env.example"
    echo ""
    echo "To run:"
    echo "  cd dist/${BINARY_NAME}"
    echo "  cp .env.example .env    # edit with your Zabbix credentials"
    echo "  ./${BINARY_NAME}"
    echo "=============================================="
fi
