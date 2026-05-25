"""
Generate Test Vectors for RTL Testbench
========================================

This script generates test vectors for the streaming attention RTL testbench:
1. Random Q, K, V matrices (INT8)
2. Computes expected output using quantized reference model
3. Writes vectors to text files for Verilog $readmemh

Output files:
- test_vectors/q_matrix.txt
- test_vectors/k_matrix.txt
- test_vectors/v_matrix.txt
- test_vectors/expected_output.txt

Author: Generated for streaming-attention-accelerator project
Date: 2026-04-01
"""

import numpy as np
import sys
import os

# Add parent directory to path to import reference model
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
from reference.attention import QuantizedAttentionReference, generate_test_vectors


def quantize_to_int8(x, scale=0.01):
    """Quantize float32 to INT8."""
    x_q = np.round(x / scale)
    x_q = np.clip(x_q, -128, 127)
    return x_q.astype(np.int8)


def write_matrix_to_file(matrix, filename):
    """
    Write matrix to text file in row-major order.
    Each element on a separate line as signed integer.
    """
    L, D = matrix.shape
    with open(filename, 'w') as f:
        for i in range(L):
            for j in range(D):
                # Write as signed integer
                val = int(matrix[i, j])
                f.write(f"{val}\n")
    print(f"  Written {filename}: {L}×{D} = {L*D} elements")


def main():
    print("="*60)
    print("Test Vector Generation for RTL Testbench")
    print("="*60)

    # Parameters
    L = 8
    D = 64
    seed = 42
    scale = 0.01

    print(f"\nParameters:")
    print(f"  Sequence length (L): {L}")
    print(f"  Embedding dim (D):   {D}")
    print(f"  Quantization scale:  {scale}")
    print(f"  Random seed:         {seed}")

    # Create output directory
    os.makedirs("test_vectors", exist_ok=True)

    # Generate random test vectors (floating-point)
    print(f"\nGenerating random test vectors...")
    Q_fp, K_fp, V_fp = generate_test_vectors(L, D, seed=seed, value_range=(-1.0, 1.0))
    print(f"  Q: {Q_fp.shape}, range [{Q_fp.min():.3f}, {Q_fp.max():.3f}]")
    print(f"  K: {K_fp.shape}, range [{K_fp.min():.3f}, {K_fp.max():.3f}]")
    print(f"  V: {V_fp.shape}, range [{V_fp.min():.3f}, {V_fp.max():.3f}]")

    # Quantize to INT8
    print(f"\nQuantizing to INT8...")
    Q_int8 = quantize_to_int8(Q_fp, scale)
    K_int8 = quantize_to_int8(K_fp, scale)
    V_int8 = quantize_to_int8(V_fp, scale)
    print(f"  Q_int8: range [{Q_int8.min()}, {Q_int8.max()}]")
    print(f"  K_int8: range [{K_int8.min()}, {K_int8.max()}]")
    print(f"  V_int8: range [{V_int8.min()}, {V_int8.max()}]")

    # Compute expected output using quantized reference
    print(f"\nComputing expected output using quantized reference model...")
    attn_ref = QuantizedAttentionReference(
        d_k=D,
        weight_scale=scale,
        activation_scale=scale,
        output_scale=scale,
        scale_shift=3  # √64 = 8 = 2^3
    )

    output_fp, weights_fp = attn_ref.forward(Q_fp, K_fp, V_fp)
    print(f"  Output: {output_fp.shape}, range [{output_fp.min():.3f}, {output_fp.max():.3f}]")
    print(f"  Attention weights: {weights_fp.shape}")
    print(f"  Attention weights sum per row: {weights_fp.sum(axis=1)}")

    # Quantize output to INT8 for comparison
    output_int8 = quantize_to_int8(output_fp, scale)
    print(f"  Output_int8: range [{output_int8.min()}, {output_int8.max()}]")

    # Write to files
    print(f"\nWriting test vectors to files...")
    write_matrix_to_file(Q_int8, "test_vectors/q_matrix.txt")
    write_matrix_to_file(K_int8, "test_vectors/k_matrix.txt")
    write_matrix_to_file(V_int8, "test_vectors/v_matrix.txt")
    write_matrix_to_file(output_int8, "test_vectors/expected_output.txt")

    # Write attention weights for debugging
    weights_int16 = (weights_fp * 32768).astype(np.int16)
    write_matrix_to_file(weights_int16, "test_vectors/attention_weights.txt")
    print(f"  Written test_vectors/attention_weights.txt (for debugging)")

    # Generate summary file
    with open("test_vectors/summary.txt", 'w') as f:
        f.write("Test Vector Summary\n")
        f.write("="*60 + "\n")
        f.write(f"Generated: {np.datetime64('now')}\n")
        f.write(f"Seed: {seed}\n")
        f.write(f"L: {L}, D: {D}\n")
        f.write(f"Quantization scale: {scale}\n")
        f.write(f"\nInput ranges (INT8):\n")
        f.write(f"  Q: [{Q_int8.min()}, {Q_int8.max()}]\n")
        f.write(f"  K: [{K_int8.min()}, {K_int8.max()}]\n")
        f.write(f"  V: [{V_int8.min()}, {V_int8.max()}]\n")
        f.write(f"\nOutput range (INT8):\n")
        f.write(f"  Output: [{output_int8.min()}, {output_int8.max()}]\n")
        f.write(f"\nAttention weights (first row):\n")
        f.write(f"  {weights_fp[0]}\n")
        f.write(f"  Sum: {weights_fp[0].sum():.6f}\n")

    print(f"  Written test_vectors/summary.txt")

    print("\n" + "="*60)
    print("Test vector generation completed successfully!")
    print("="*60)
    print("\nFiles created:")
    print("  test_vectors/q_matrix.txt")
    print("  test_vectors/k_matrix.txt")
    print("  test_vectors/v_matrix.txt")
    print("  test_vectors/expected_output.txt")
    print("  test_vectors/attention_weights.txt")
    print("  test_vectors/summary.txt")
    print("\nYou can now run the RTL testbench with these vectors.")


if __name__ == "__main__":
    main()
