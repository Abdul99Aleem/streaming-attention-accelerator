#!/bin/bash
#==============================================================================
# Python Environment Setup Script
# Description: Sets up Python virtual environment with all dependencies
#
# Usage:
#   ./setup_python_env.sh
#
# Creates:
#   - Virtual environment in project root (.venv)
#   - Installs numpy and other dependencies
#   - Activates environment
#
# Author: Generated for streaming-attention-accelerator project
# Date: 2026-04-01
#==============================================================================

set -e  # Exit on error

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="$PROJECT_ROOT/.venv"

echo "========================================================================"
echo "Python Environment Setup"
echo "========================================================================"
echo ""

# Check if Python 3 is available
if ! command -v python3 &> /dev/null; then
    echo "[ERROR] Python 3 not found. Please install Python 3.8 or later."
    exit 1
fi

PYTHON_VERSION=$(python3 --version)
echo "[INFO] Found $PYTHON_VERSION"

# Create virtual environment if it doesn't exist
if [ -d "$VENV_DIR" ]; then
    echo "[INFO] Virtual environment already exists at $VENV_DIR"
else
    echo "[INFO] Creating virtual environment at $VENV_DIR"
    python3 -m venv "$VENV_DIR"
    echo "[SUCCESS] Virtual environment created"
fi

# Activate virtual environment
echo "[INFO] Activating virtual environment"
source "$VENV_DIR/bin/activate"

# Upgrade pip
echo "[INFO] Upgrading pip"
pip install --upgrade pip

# Install dependencies
echo "[INFO] Installing dependencies from requirements.txt"
pip install -r "$PROJECT_ROOT/python/requirements.txt"

echo ""
echo "========================================================================"
echo "Setup Complete!"
echo "========================================================================"
echo ""
echo "Virtual environment is now active."
echo ""
echo "To activate in future sessions:"
echo "  source .venv/bin/activate"
echo ""
echo "To deactivate:"
echo "  deactivate"
echo ""
echo "Next steps:"
echo "  1. Run Python tests: python3 python/reference/attention.py"
echo "  2. Generate test vectors: python3 python/verification/generate_test_vectors.py"
echo ""
