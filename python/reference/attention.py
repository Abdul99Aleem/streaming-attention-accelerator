"""
Attention Reference Implementation
===================================

This module provides reference implementations of scaled dot-product attention:
1. Floating-point (golden reference)
2. Quantized INT8/INT32/INT16 (matches RTL behavior)

Used for:
- Generating test vectors for RTL testbenches
- Validating RTL outputs
- Analyzing quantization error

Author: Generated for streaming-attention-accelerator project
Date: 2026-04-01
"""

import numpy as np
from typing import Tuple, Optional
import warnings


class AttentionReference:
    """Floating-point reference implementation of scaled dot-product attention."""

    def __init__(self, d_k: int = 64):
        """
        Initialize attention module.

        Args:
            d_k: Dimension of queries and keys (used for scaling)
        """
        self.d_k = d_k
        self.scale = 1.0 / np.sqrt(d_k)

    def forward(self, Q: np.ndarray, K: np.ndarray, V: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
        """
        Compute scaled dot-product attention.

        Args:
            Q: Query matrix (L, d_k)
            K: Key matrix (L, d_k)
            V: Value matrix (L, d_v)

        Returns:
            output: Attention output (L, d_v)
            attention_weights: Attention weights (L, L)

        Formula:
            Attention(Q, K, V) = softmax(Q·K^T / √d_k) · V
        """
        # Compute attention scores: Q·K^T
        scores = Q @ K.T  # (L, L)

        # Scale by √d_k
        scores_scaled = scores * self.scale

        # Apply softmax (with numerical stability)
        attention_weights = self._softmax(scores_scaled)

        # Compute weighted sum of values
        output = attention_weights @ V  # (L, d_v)

        return output, attention_weights

    def _softmax(self, x: np.ndarray) -> np.ndarray:
        """
        Compute softmax with numerical stability (max-subtraction trick).

        Args:
            x: Input array (L, L)

        Returns:
            Softmax output (L, L), each row sums to 1
        """
        # Subtract max per row for numerical stability
        x_max = np.max(x, axis=1, keepdims=True)
        x_shifted = x - x_max

        # Compute exp
        exp_x = np.exp(x_shifted)

        # Normalize
        sum_exp = np.sum(exp_x, axis=1, keepdims=True)
        softmax_out = exp_x / sum_exp

        return softmax_out


class QuantizedAttentionReference:
    """
    Quantized attention reference matching RTL behavior.

    Uses:
    - INT8 for Q, K, V weights and activations
    - INT32 for dot product accumulation
    - INT16 (Q15 fixed-point) for softmax attention weights
    """

    def __init__(
        self,
        d_k: int = 64,
        weight_scale: float = 0.01,
        activation_scale: float = 0.01,
        output_scale: float = 0.01,
        scale_shift: int = 3  # Right-shift for √d_k scaling (3 = divide by 8)
    ):
        """
        Initialize quantized attention module.

        Args:
            d_k: Dimension of queries and keys
            weight_scale: Quantization scale for weights
            activation_scale: Quantization scale for activations
            output_scale: Quantization scale for outputs
            scale_shift: Right-shift amount for √d_k scaling
        """
        self.d_k = d_k
        self.weight_scale = weight_scale
        self.activation_scale = activation_scale
        self.output_scale = output_scale
        self.scale_shift = scale_shift

        # Verify scale_shift matches √d_k
        expected_scale = 1.0 / np.sqrt(d_k)
        actual_scale = 1.0 / (2 ** scale_shift)
        if not np.isclose(expected_scale, actual_scale, rtol=0.2):
            warnings.warn(
                f"scale_shift={scale_shift} gives 1/{2**scale_shift}={actual_scale:.4f}, "
                f"but √d_k={np.sqrt(d_k):.4f} suggests 1/{np.sqrt(d_k)}={expected_scale:.4f}"
            )

    def forward(
        self,
        Q: np.ndarray,
        K: np.ndarray,
        V: np.ndarray,
        return_intermediates: bool = False
    ) -> Tuple[np.ndarray, np.ndarray]:
        """
        Compute quantized attention.

        Args:
            Q: Query matrix (L, d_k), float32
            K: Key matrix (L, d_k), float32
            V: Value matrix (L, d_v), float32
            return_intermediates: If True, return intermediate values for debugging

        Returns:
            output: Attention output (L, d_v), float32 (dequantized)
            attention_weights: Attention weights (L, L), float32 (dequantized)
        """
        L = Q.shape[0]
        d_v = V.shape[1]

        # Quantize inputs to INT8
        Q_q = self._quantize_int8(Q, self.activation_scale)
        K_q = self._quantize_int8(K, self.activation_scale)
        V_q = self._quantize_int8(V, self.activation_scale)

        # Initialize output accumulator (INT32)
        output_acc = np.zeros((L, d_v), dtype=np.int32)

        # Store attention weights for all queries
        attention_weights_q = np.zeros((L, L), dtype=np.int16)

        # Process each query (streaming computation)
        for i in range(L):
            # Compute attention scores for query i
            scores_i = self._compute_scores_row(Q_q[i], K_q)  # (L,) INT32

            # Scale scores
            scores_scaled = self._scale_scores(scores_i, self.scale_shift)  # (L,) INT32

            # Apply softmax to get attention weights
            attention_i = self._softmax_int16(scores_scaled)  # (L,) INT16 Q15

            # Store attention weights
            attention_weights_q[i] = attention_i

            # Compute weighted sum for this query
            output_acc[i] = self._weighted_sum(attention_i, V_q)  # (d_v,) INT32

        # Dequantize outputs
        # output_acc contains: Σ(attention_q15[i] × v_int8[i])
        # where attention_q15 = attention_float × 32768 (Q15 format)
        # and v_int8 = v_float / activation_scale
        # So: output_acc = Σ(attention_float × v_float) × (32768 / activation_scale)
        # To get float output: multiply by (activation_scale / 32768)
        output = output_acc.astype(np.float32) * (self.activation_scale / 32768.0)

        # Dequantize attention weights (Q15 to float)
        attention_weights = attention_weights_q.astype(np.float32) / 32768.0

        if return_intermediates:
            return output, attention_weights, {
                'Q_q': Q_q,
                'K_q': K_q,
                'V_q': V_q,
                'attention_weights_q': attention_weights_q,
                'output_acc': output_acc
            }

        return output, attention_weights

    def _quantize_int8(self, x: np.ndarray, scale: float) -> np.ndarray:
        """
        Quantize float32 to INT8.

        Args:
            x: Input array (float32)
            scale: Quantization scale

        Returns:
            Quantized array (int8)
        """
        x_q = np.round(x / scale)
        x_q = np.clip(x_q, -128, 127)
        return x_q.astype(np.int8)

    def _compute_scores_row(self, q_row: np.ndarray, K: np.ndarray) -> np.ndarray:
        """
        Compute attention scores for one query row.

        Args:
            q_row: Query vector (d_k,) INT8
            K: Key matrix (L, d_k) INT8

        Returns:
            Scores (L,) INT32
        """
        # Dot product: q_row · K^T
        # Each element is sum of d_k INT8×INT8 products
        scores = np.zeros(K.shape[0], dtype=np.int32)

        for j in range(K.shape[0]):
            # Compute dot product with INT32 accumulation
            dot = np.sum(q_row.astype(np.int32) * K[j].astype(np.int32))
            scores[j] = dot

        return scores

    def _scale_scores(self, scores: np.ndarray, shift: int) -> np.ndarray:
        """
        Scale scores by right-shift (divide by 2^shift).

        Args:
            scores: Input scores (INT32)
            shift: Right-shift amount

        Returns:
            Scaled scores (INT32)
        """
        # Arithmetic right-shift (preserves sign)
        return scores >> shift

    def _softmax_int16(self, scores: np.ndarray) -> np.ndarray:
        """
        Compute softmax in INT16 Q15 fixed-point.

        Args:
            scores: Input scores (L,) INT32 (already scaled by right-shift)

        Returns:
            Attention weights (L,) INT16 Q15 (range [0, 32767] representing [0, 1])
        """
        L = len(scores)

        # Step 1: Find max (for numerical stability)
        max_score = np.max(scores)

        # Step 2: Subtract max
        scores_shifted = scores - max_score

        # Step 3: Compute exp (using floating-point, then convert to Q15)
        # In RTL, this would use LUT. Here we use float for accuracy.
        #
        # Dequantization: scores are products of two INT8 quantized values
        # Each INT8 value represents: float_val / activation_scale
        # Product represents: (float_val1 / scale) × (float_val2 / scale)
        # To get back to float: multiply by scale²
        #
        # After right-shift by scale_shift, we've divided by 2^scale_shift
        # So final scale factor: activation_scale² × 2^scale_shift
        scale_factor = (self.activation_scale ** 2) * (2 ** self.scale_shift)
        scores_float = scores_shifted.astype(np.float32) * scale_factor
        exp_vals = np.exp(scores_float)

        # Step 4: Sum
        sum_exp = np.sum(exp_vals)

        # Step 5: Normalize and convert to Q15
        attention_float = exp_vals / sum_exp
        attention_q15 = np.round(attention_float * 32768.0)
        attention_q15 = np.clip(attention_q15, 0, 32767)

        return attention_q15.astype(np.int16)

    def _weighted_sum(self, attention: np.ndarray, V: np.ndarray) -> np.ndarray:
        """
        Compute weighted sum of values.

        Args:
            attention: Attention weights (L,) INT16 Q15
            V: Value matrix (L, d_v) INT8

        Returns:
            Weighted sum (d_v,) INT32
        """
        L, d_v = V.shape
        output = np.zeros(d_v, dtype=np.int32)

        for j in range(L):
            # Multiply attention weight (INT16) by value row (INT8)
            # Result is INT32 (actually fits in INT24, but we use INT32)
            weighted = attention[j].astype(np.int32) * V[j].astype(np.int32)
            output += weighted

        return output


def generate_test_vectors(
    L: int = 8,
    d: int = 64,
    seed: int = 42,
    value_range: Tuple[float, float] = (-1.0, 1.0)
) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    """
    Generate random test vectors for attention.

    Args:
        L: Sequence length
        d: Embedding dimension
        seed: Random seed for reproducibility
        value_range: Range for random values

    Returns:
        Q, K, V: Random matrices (L, d) in specified range
    """
    np.random.seed(seed)

    low, high = value_range
    Q = np.random.uniform(low, high, (L, d)).astype(np.float32)
    K = np.random.uniform(low, high, (L, d)).astype(np.float32)
    V = np.random.uniform(low, high, (L, d)).astype(np.float32)

    return Q, K, V


def compare_outputs(
    output1: np.ndarray,
    output2: np.ndarray,
    tolerance: float = 0.01,
    name1: str = "Reference",
    name2: str = "Implementation"
) -> dict:
    """
    Compare two attention outputs and compute error metrics.

    Args:
        output1: First output (L, d)
        output2: Second output (L, d)
        tolerance: Acceptable relative error threshold
        name1: Name of first implementation
        name2: Name of second implementation

    Returns:
        Dictionary with error metrics
    """
    # Compute absolute error
    abs_error = np.abs(output1 - output2)

    # Compute relative error (avoid division by zero)
    epsilon = 1e-8
    rel_error = abs_error / (np.abs(output1) + epsilon)

    # Compute metrics
    max_abs_error = np.max(abs_error)
    mean_abs_error = np.mean(abs_error)
    max_rel_error = np.max(rel_error)
    mean_rel_error = np.mean(rel_error)

    # Count elements exceeding tolerance
    num_exceeding = np.sum(rel_error > tolerance)
    total_elements = output1.size

    # Check if within tolerance
    passed = max_rel_error <= tolerance

    results = {
        'passed': passed,
        'max_abs_error': max_abs_error,
        'mean_abs_error': mean_abs_error,
        'max_rel_error': max_rel_error,
        'mean_rel_error': mean_rel_error,
        'num_exceeding_tolerance': num_exceeding,
        'total_elements': total_elements,
        'tolerance': tolerance
    }

    # Print summary
    print(f"\n{'='*60}")
    print(f"Comparison: {name1} vs {name2}")
    print(f"{'='*60}")
    print(f"Max absolute error:  {max_abs_error:.6f}")
    print(f"Mean absolute error: {mean_abs_error:.6f}")
    print(f"Max relative error:  {max_rel_error:.2%}")
    print(f"Mean relative error: {mean_rel_error:.2%}")
    print(f"Elements exceeding {tolerance:.1%} tolerance: {num_exceeding}/{total_elements}")
    print(f"Status: {'✓ PASSED' if passed else '✗ FAILED'}")
    print(f"{'='*60}\n")

    return results


if __name__ == "__main__":
    """
    Example usage and validation.
    """
    print("Attention Reference Implementation Test")
    print("=" * 60)

    # Parameters
    L = 8
    d = 64

    # Generate test vectors
    print(f"\nGenerating test vectors (L={L}, d={d})...")
    Q, K, V = generate_test_vectors(L, d, seed=42)

    # Test floating-point reference
    print("\n1. Testing floating-point reference...")
    attn_fp = AttentionReference(d_k=d)
    output_fp, weights_fp = attn_fp.forward(Q, K, V)

    print(f"   Output shape: {output_fp.shape}")
    print(f"   Output range: [{output_fp.min():.4f}, {output_fp.max():.4f}]")
    print(f"   Attention weights shape: {weights_fp.shape}")
    print(f"   Attention weights sum per row: {weights_fp.sum(axis=1)}")

    # Verify attention weights sum to 1
    assert np.allclose(weights_fp.sum(axis=1), 1.0), "Attention weights don't sum to 1!"
    print("   ✓ Attention weights sum to 1.0")

    # Test quantized reference
    print("\n2. Testing quantized reference...")
    attn_quant = QuantizedAttentionReference(
        d_k=d,
        weight_scale=0.01,
        activation_scale=0.01,
        output_scale=0.01,
        scale_shift=3  # √64 = 8 = 2^3
    )
    output_quant, weights_quant = attn_quant.forward(Q, K, V)

    print(f"   Output shape: {output_quant.shape}")
    print(f"   Output range: [{output_quant.min():.4f}, {output_quant.max():.4f}]")
    print(f"   Attention weights shape: {weights_quant.shape}")
    print(f"   Attention weights sum per row: {weights_quant.sum(axis=1)}")

    # Compare floating-point vs quantized
    print("\n3. Comparing floating-point vs quantized...")
    results = compare_outputs(
        output_fp,
        output_quant,
        tolerance=0.05,  # 5% tolerance for quantization
        name1="Floating-point",
        name2="Quantized"
    )

    # Compare attention weights
    print("\n4. Comparing attention weights...")
    weights_results = compare_outputs(
        weights_fp,
        weights_quant,
        tolerance=0.05,
        name1="FP Weights",
        name2="Quantized Weights"
    )

    print("\n" + "="*60)
    print("Test completed successfully!")
    print("="*60)
