"""
Python wrapper for Streaming Attention Accelerator v4

This module provides a Python interface to the attention accelerator
hardware via the C driver library.

Author: Generated for streaming-attention-accelerator project
Date: 2026-04-03
"""

import ctypes
import numpy as np
from typing import Tuple, Optional
import os

# Load C library (adjust path as needed)
_lib_path = os.path.join(os.path.dirname(__file__), 'libattention_accel.so')
try:
    _lib = ctypes.CDLL(_lib_path)
except OSError:
    print(f"Warning: Could not load {_lib_path}")
    print("Hardware acceleration not available. Using software fallback.")
    _lib = None

#==============================================================================
# C Structure Definitions
#==============================================================================

class AttnDevice(ctypes.Structure):
    """Attention accelerator device structure"""
    _fields_ = [
        ('base_addr', ctypes.POINTER(ctypes.c_uint32)),
        ('q_mem_addr', ctypes.c_uint32),
        ('k_mem_addr', ctypes.c_uint32),
        ('v_mem_addr', ctypes.c_uint32),
        ('out_mem_addr', ctypes.c_uint32),
        ('L', ctypes.c_uint8),
        ('D', ctypes.c_uint8),
        ('scale_shift', ctypes.c_uint8),
    ]

class AttnConfig(ctypes.Structure):
    """Attention computation configuration"""
    _fields_ = [
        ('L', ctypes.c_uint8),
        ('D', ctypes.c_uint8),
        ('scale_shift', ctypes.c_uint8),
        ('use_interrupt', ctypes.c_bool),
        ('timeout_ms', ctypes.c_uint32),
    ]

class AttnResult(ctypes.Structure):
    """Attention computation result"""
    _fields_ = [
        ('cycle_count', ctypes.c_uint32),
        ('latency_us', ctypes.c_float),
        ('success', ctypes.c_bool),
        ('timeout', ctypes.c_bool),
        ('error', ctypes.c_bool),
    ]

#==============================================================================
# C Function Prototypes
#==============================================================================

if _lib:
    # attn_init
    _lib.attn_init.argtypes = [
        ctypes.POINTER(AttnDevice),
        ctypes.POINTER(ctypes.c_uint32),
        ctypes.c_uint32,
        ctypes.c_uint32,
        ctypes.c_uint32,
        ctypes.c_uint32,
    ]
    _lib.attn_init.restype = ctypes.c_int

    # attn_configure
    _lib.attn_configure.argtypes = [
        ctypes.POINTER(AttnDevice),
        ctypes.POINTER(AttnConfig),
    ]
    _lib.attn_configure.restype = ctypes.c_int

    # attn_compute
    _lib.attn_compute.argtypes = [
        ctypes.POINTER(AttnDevice),
        ctypes.POINTER(ctypes.c_int8),
        ctypes.POINTER(ctypes.c_int8),
        ctypes.POINTER(ctypes.c_int8),
        ctypes.POINTER(ctypes.c_int8),
        ctypes.POINTER(AttnResult),
    ]
    _lib.attn_compute.restype = ctypes.c_int

    # attn_get_version
    _lib.attn_get_version.argtypes = [
        ctypes.POINTER(AttnDevice),
        ctypes.POINTER(ctypes.c_uint16),
        ctypes.POINTER(ctypes.c_uint16),
    ]
    _lib.attn_get_version.restype = ctypes.c_int

#==============================================================================
# Python Class
#==============================================================================

class AttentionAccelerator:
    """
    Python interface to the Streaming Attention Accelerator v4

    This class provides a high-level Python API for the attention
    accelerator hardware.

    Example:
        >>> accel = AttentionAccelerator(axi_base=0x43C00000)
        >>> Q = np.random.randint(-128, 127, (8, 64), dtype=np.int8)
        >>> K = np.random.randint(-128, 127, (8, 64), dtype=np.int8)
        >>> V = np.random.randint(-128, 127, (8, 64), dtype=np.int8)
        >>> output, result = accel.compute(Q, K, V)
        >>> print(f"Latency: {result['latency_us']:.2f} us")
    """

    def __init__(self,
                 axi_base: int = 0x43C00000,
                 q_mem: int = 0x10000000,
                 k_mem: int = 0x10001000,
                 v_mem: int = 0x10002000,
                 out_mem: int = 0x10003000):
        """
        Initialize attention accelerator

        Args:
            axi_base: Base address of AXI registers
            q_mem: Q matrix memory address
            k_mem: K matrix memory address
            v_mem: V matrix memory address
            out_mem: Output memory address
        """
        if _lib is None:
            raise RuntimeError("Hardware library not available")

        self.dev = AttnDevice()
        self.axi_base = ctypes.cast(axi_base, ctypes.POINTER(ctypes.c_uint32))

        ret = _lib.attn_init(
            ctypes.byref(self.dev),
            self.axi_base,
            q_mem,
            k_mem,
            v_mem,
            out_mem
        )

        if ret < 0:
            raise RuntimeError(f"Failed to initialize accelerator: {ret}")

    def configure(self,
                  L: int = 8,
                  D: int = 64,
                  scale_shift: int = 3,
                  use_interrupt: bool = False,
                  timeout_ms: int = 1000):
        """
        Configure attention accelerator

        Args:
            L: Sequence length (1-16)
            D: Embedding dimension (16-64)
            scale_shift: Scaling factor (0-7)
            use_interrupt: Use interrupt instead of polling
            timeout_ms: Timeout in milliseconds
        """
        config = AttnConfig()
        config.L = L
        config.D = D
        config.scale_shift = scale_shift
        config.use_interrupt = use_interrupt
        config.timeout_ms = timeout_ms

        ret = _lib.attn_configure(ctypes.byref(self.dev), ctypes.byref(config))

        if ret < 0:
            raise RuntimeError(f"Failed to configure accelerator: {ret}")

    def compute(self,
                Q: np.ndarray,
                K: np.ndarray,
                V: np.ndarray) -> Tuple[np.ndarray, dict]:
        """
        Compute attention: softmax(Q·K^T / √d_k) · V

        Args:
            Q: Query matrix (L×D, int8)
            K: Key matrix (L×D, int8)
            V: Value matrix (L×D, int8)

        Returns:
            output: Output matrix (L×D, int8)
            result: Dictionary with computation metrics
        """
        # Validate inputs
        if Q.shape != K.shape or Q.shape != V.shape:
            raise ValueError("Q, K, V must have same shape")

        L, D = Q.shape

        if Q.dtype != np.int8:
            raise ValueError("Q must be int8")
        if K.dtype != np.int8:
            raise ValueError("K must be int8")
        if V.dtype != np.int8:
            raise ValueError("V must be int8")

        # Configure for this computation
        scale_shift = int(np.log2(np.sqrt(D)))
        self.configure(L=L, D=D, scale_shift=scale_shift)

        # Prepare output buffer
        output = np.zeros((L, D), dtype=np.int8)

        # Prepare result structure
        result = AttnResult()

        # Call C function
        ret = _lib.attn_compute(
            ctypes.byref(self.dev),
            Q.ctypes.data_as(ctypes.POINTER(ctypes.c_int8)),
            K.ctypes.data_as(ctypes.POINTER(ctypes.c_int8)),
            V.ctypes.data_as(ctypes.POINTER(ctypes.c_int8)),
            output.ctypes.data_as(ctypes.POINTER(ctypes.c_int8)),
            ctypes.byref(result)
        )

        if ret < 0:
            raise RuntimeError(f"Computation failed: {ret}")

        # Convert result to dict
        result_dict = {
            'cycle_count': result.cycle_count,
            'latency_us': result.latency_us,
            'throughput': 1e6 / result.latency_us if result.latency_us > 0 else 0,
            'success': result.success,
            'timeout': result.timeout,
            'error': result.error,
        }

        return output, result_dict

    def get_version(self) -> Tuple[int, int]:
        """
        Get accelerator version

        Returns:
            major: Major version
            minor: Minor version
        """
        major = ctypes.c_uint16()
        minor = ctypes.c_uint16()

        ret = _lib.attn_get_version(
            ctypes.byref(self.dev),
            ctypes.byref(major),
            ctypes.byref(minor)
        )

        if ret < 0:
            raise RuntimeError(f"Failed to get version: {ret}")

        return major.value, minor.value

    def __repr__(self):
        try:
            major, minor = self.get_version()
            return f"AttentionAccelerator(version=v{major}.{minor}, L={self.dev.L}, D={self.dev.D})"
        except:
            return "AttentionAccelerator(not initialized)"

#==============================================================================
# Software Fallback (for testing without hardware)
#==============================================================================

class AttentionAcceleratorSoftware:
    """
    Software fallback implementation for testing without hardware

    This class provides the same API as AttentionAccelerator but
    uses pure Python/NumPy implementation.
    """

    def __init__(self, **kwargs):
        """Initialize software fallback"""
        self.L = 8
        self.D = 64
        self.scale_shift = 3

    def configure(self, L=8, D=64, scale_shift=3, **kwargs):
        """Configure parameters"""
        self.L = L
        self.D = D
        self.scale_shift = scale_shift

    def compute(self, Q, K, V):
        """
        Software attention computation

        Uses floating-point for accuracy, then quantizes to int8
        """
        import time

        start = time.time()

        # Convert to float
        Q_f = Q.astype(np.float32)
        K_f = K.astype(np.float32)
        V_f = V.astype(np.float32)

        # Compute scores: Q·K^T
        scores = Q_f @ K_f.T

        # Scale
        scores = scores / (2 ** self.scale_shift)

        # Softmax
        scores_exp = np.exp(scores - np.max(scores, axis=1, keepdims=True))
        attention = scores_exp / np.sum(scores_exp, axis=1, keepdims=True)

        # Weighted sum: A·V
        output_f = attention @ V_f

        # Quantize to int8
        output = np.clip(output_f, -128, 127).astype(np.int8)

        elapsed = time.time() - start

        result = {
            'cycle_count': 0,  # N/A for software
            'latency_us': elapsed * 1e6,
            'throughput': 1.0 / elapsed,
            'success': True,
            'timeout': False,
            'error': False,
        }

        return output, result

    def get_version(self):
        """Return software version"""
        return (0, 1)  # v0.1 = software fallback

    def __repr__(self):
        return f"AttentionAcceleratorSoftware(L={self.L}, D={self.D})"

#==============================================================================
# Factory Function
#==============================================================================

def create_accelerator(use_hardware=True, **kwargs):
    """
    Create attention accelerator instance

    Args:
        use_hardware: Try to use hardware if available
        **kwargs: Arguments passed to accelerator constructor

    Returns:
        Accelerator instance (hardware or software fallback)
    """
    if use_hardware and _lib is not None:
        try:
            return AttentionAccelerator(**kwargs)
        except Exception as e:
            print(f"Hardware initialization failed: {e}")
            print("Falling back to software implementation")

    return AttentionAcceleratorSoftware(**kwargs)

#==============================================================================
# Example Usage
#==============================================================================

if __name__ == '__main__':
    # Create accelerator (will use software fallback if hardware not available)
    accel = create_accelerator(use_hardware=False)

    print(f"Using: {accel}")
    print()

    # Generate test data
    L, D = 8, 64
    Q = np.random.randint(-128, 127, (L, D), dtype=np.int8)
    K = np.random.randint(-128, 127, (L, D), dtype=np.int8)
    V = np.random.randint(-128, 127, (L, D), dtype=np.int8)

    print(f"Input shapes: Q={Q.shape}, K={K.shape}, V={V.shape}")
    print()

    # Compute attention
    output, result = accel.compute(Q, K, V)

    print(f"Output shape: {output.shape}")
    print(f"Output dtype: {output.dtype}")
    print()

    print("Performance:")
    print(f"  Latency:    {result['latency_us']:.2f} us")
    print(f"  Throughput: {result['throughput']:.0f} att/sec")
    print(f"  Success:    {result['success']}")
    print()

    print("Sample output (first row, first 8 elements):")
    print(output[0, :8])
