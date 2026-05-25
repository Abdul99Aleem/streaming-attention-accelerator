#!/bin/bash
#==============================================================================
# Simulation Script for Streaming Attention Accelerator
# Description: Compiles and runs RTL testbenches using Vivado XSim
#
# Usage:
#   ./run_sim.sh <testbench>
#
# Examples:
#   ./run_sim.sh mac           # Run MAC unit test
#   ./run_sim.sh attention     # Run full attention integration test
#   ./run_sim.sh all           # Run all tests
#
# Requirements:
#   - Vivado installed and in PATH
#   - Test vectors generated (run generate_test_vectors.py first)
#
# Author: Generated for streaming-attention-accelerator project
# Date: 2026-04-01
#==============================================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Project directories
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RTL_DIR="$PROJECT_ROOT/rtl"
TB_DIR="$PROJECT_ROOT/tb"
SIM_DIR="$TB_DIR/scripts/sim"
PYTHON_DIR="$PROJECT_ROOT/python"

# Create simulation directory
mkdir -p "$SIM_DIR"
cd "$SIM_DIR"

#==============================================================================
# Helper Functions
#==============================================================================

print_header() {
    echo ""
    echo "========================================================================"
    echo "$1"
    echo "========================================================================"
    echo ""
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

#==============================================================================
# Test Functions
#==============================================================================

run_mac_test() {
    print_header "Running MAC Unit Test"

    # Compile
    print_info "Compiling RTL and testbench..."
    xvlog --sv \
        "$RTL_DIR/primitives/mac_int8.v" \
        "$TB_DIR/unit/tb_mac_int8.v" \
        || { print_error "Compilation failed"; return 1; }

    # Elaborate
    print_info "Elaborating design..."
    xelab -debug typical tb_mac_int8 -s mac_sim \
        || { print_error "Elaboration failed"; return 1; }

    # Simulate
    print_info "Running simulation..."
    xsim mac_sim -runall \
        || { print_error "Simulation failed"; return 1; }

    print_success "MAC unit test completed"
}

run_softmax_test() {
    print_header "Running Softmax Unit Test"

    # Compile
    print_info "Compiling RTL and testbench..."
    xvlog --sv \
        "$RTL_DIR/softmax/softmax_unit_v2.v" \
        "$TB_DIR/unit/tb_softmax_unit.v" \
        || { print_error "Compilation failed"; return 1; }

    # Elaborate
    print_info "Elaborating design..."
    xelab -debug typical tb_softmax_unit -s softmax_sim \
        || { print_error "Elaboration failed"; return 1; }

    # Simulate
    print_info "Running simulation..."
    xsim softmax_sim -runall \
        || { print_error "Simulation failed"; return 1; }

    print_success "Softmax unit test completed"
}

run_dotproduct_test() {
    print_header "Running Dot Product Engine Unit Test"

    # Compile
    print_info "Compiling RTL and testbench..."
    xvlog --sv \
        "$RTL_DIR/primitives/mac_int8.v" \
        "$RTL_DIR/compute/dot_product_engine.v" \
        "$TB_DIR/unit/tb_dot_product_engine.v" \
        || { print_error "Compilation failed"; return 1; }

    # Elaborate
    print_info "Elaborating design..."
    xelab -debug typical tb_dot_product_engine -s dotproduct_sim \
        || { print_error "Elaboration failed"; return 1; }

    # Simulate
    print_info "Running simulation..."
    xsim dotproduct_sim -runall \
        || { print_error "Simulation failed"; return 1; }

    print_success "Dot product engine test completed"
}

run_attention_test() {
    print_header "Running Streaming Attention Integration Test"

    # Check if test vectors exist
    if [ ! -f "$PROJECT_ROOT/test_vectors/q_matrix.txt" ]; then
        print_info "Test vectors not found. Generating..."
        cd "$PYTHON_DIR/verification"
        python3 generate_test_vectors.py
        cd "$SIM_DIR"
    fi

    # Compile
    print_info "Compiling RTL and testbench..."
    xvlog --sv \
        "$RTL_DIR/primitives/mac_int8.v" \
        "$RTL_DIR/compute/dot_product_engine.v" \
        "$RTL_DIR/softmax/softmax_unit_v2.v" \
        "$RTL_DIR/attention/streaming_attention_v3.v" \
        "$TB_DIR/integration/tb_streaming_attention.v" \
        || { print_error "Compilation failed"; return 1; }

    # Elaborate
    print_info "Elaborating design..."
    xelab -debug typical tb_streaming_attention -s attention_sim \
        || { print_error "Elaboration failed"; return 1; }

    # Simulate
    print_info "Running simulation..."
    xsim attention_sim -runall \
        || { print_error "Simulation failed"; return 1; }

    print_success "Streaming attention test completed"
}

run_python_tests() {
    print_header "Running Python Reference Model Tests"

    cd "$PYTHON_DIR/reference"
    python3 attention.py
    cd "$SIM_DIR"

    print_success "Python tests completed"
}

generate_test_vectors() {
    print_header "Generating Test Vectors"

    cd "$PYTHON_DIR/verification"
    python3 generate_test_vectors.py
    cd "$SIM_DIR"

    print_success "Test vectors generated"
}

#==============================================================================
# Main Script
#==============================================================================

print_header "Streaming Attention Accelerator - Simulation Runner"

# Check if Vivado is available
if ! command -v xvlog &> /dev/null; then
    print_error "Vivado XSim not found in PATH"
    print_info "Please source Vivado settings: source /path/to/Vivado/settings64.sh"
    exit 1
fi

# Parse command line arguments
TEST_NAME="${1:-all}"

case "$TEST_NAME" in
    mac)
        run_mac_test
        ;;

    softmax)
        run_softmax_test
        ;;

    dotproduct)
        run_dotproduct_test
        ;;

    attention)
        run_attention_test
        ;;

    python)
        run_python_tests
        ;;

    vectors)
        generate_test_vectors
        ;;

    unit)
        print_info "Running all unit tests..."
        run_mac_test
        run_softmax_test
        run_dotproduct_test
        print_header "Unit Tests Completed"
        ;;

    all)
        print_info "Running all tests..."
        run_python_tests
        generate_test_vectors
        run_mac_test
        run_softmax_test
        run_dotproduct_test
        run_attention_test
        print_header "All Tests Completed"
        ;;

    clean)
        print_info "Cleaning simulation files..."
        rm -rf "$SIM_DIR"/*
        print_success "Simulation directory cleaned"
        ;;

    *)
        echo "Usage: $0 {mac|softmax|dotproduct|attention|unit|python|vectors|all|clean}"
        echo ""
        echo "Tests:"
        echo "  mac        - Run MAC unit test"
        echo "  softmax    - Run softmax unit test"
        echo "  dotproduct - Run dot product engine unit test"
        echo "  attention  - Run streaming attention integration test"
        echo "  unit       - Run all unit tests"
        echo "  python     - Run Python reference model tests"
        echo "  vectors    - Generate test vectors"
        echo "  all        - Run all tests"
        echo "  clean      - Clean simulation files"
        exit 1
        ;;
esac

print_header "Simulation Complete"
