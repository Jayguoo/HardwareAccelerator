#!/usr/bin/env python3
"""
matmul_reference.py — NumPy Reference Model for Matrix Multiply Accelerator

Generates test vectors (matrices A, B) and expected results (C = A * B)
as .hex files compatible with SystemVerilog $readmemh.

Usage:
    python matmul_reference.py [--dim N] [--num-tests N] [--output-dir DIR]
"""

import argparse
import numpy as np
from pathlib import Path


def generate_matrices(n: int, data_width: int = 16, seed: int = None,
                      rng: np.random.Generator = None) -> tuple:
    """Generate random NxN matrices A and B with bounded values."""
    if rng is None:
        rng = np.random.default_rng(seed)

    # Safe max to prevent accumulator overflow (32-bit signed)
    safe_max = int(np.sqrt(2**31 / n))
    max_val = min(safe_max, 2**(data_width - 1) - 1)

    A = rng.integers(-max_val, max_val + 1, size=(n, n), dtype=np.int16)
    B = rng.integers(-max_val, max_val + 1, size=(n, n), dtype=np.int16)
    C = (A.astype(np.int64) @ B.astype(np.int64)).astype(np.int32)

    return A, B, C


def to_twos_complement(val: int, bits: int) -> int:
    """Convert signed integer to unsigned two's complement representation."""
    if val < 0:
        val = val + (1 << bits)
    return val & ((1 << bits) - 1)


def write_hex_file(matrix: np.ndarray, filepath: Path, bits: int = 32):
    """Write matrix to hex file for $readmemh (row-major order)."""
    hex_width = bits // 4
    with open(filepath, 'w') as f:
        f.write(f"// {matrix.shape[0]}x{matrix.shape[1]} matrix, {bits}-bit hex\n")
        for row in matrix:
            for val in row:
                unsigned = to_twos_complement(int(val), bits)
                f.write(f"{unsigned:0{hex_width}x}\n")


def read_hex_file(filepath: Path, shape: tuple, bits: int = 32) -> np.ndarray:
    """Read hex file and return as signed numpy array."""
    values = []
    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('//'):
                continue
            unsigned = int(line, 16)
            # Convert from unsigned to signed
            if unsigned >= (1 << (bits - 1)):
                signed_val = unsigned - (1 << bits)
            else:
                signed_val = unsigned
            values.append(signed_val)

    return np.array(values, dtype=np.int32).reshape(shape)


def generate_test_vectors(n: int = 4, num_tests: int = 5, seed: int = 42,
                          output_dir: Path = None):
    """Generate multiple test vector sets."""
    if output_dir is None:
        output_dir = Path(__file__).parent.parent.parent / 'sim' / 'test_data'

    output_dir.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(seed)

    print(f"Generating {num_tests} test vectors for {n}x{n} matrices...")
    print(f"Output directory: {output_dir}")

    for i in range(num_tests):
        A, B, C = generate_matrices(n, rng=rng)

        # Write hex files
        write_hex_file(A.astype(np.int32), output_dir / f"mat_a_{i}.hex", bits=32)
        write_hex_file(B.astype(np.int32), output_dir / f"mat_b_{i}.hex", bits=32)
        write_hex_file(C, output_dir / f"mat_c_expected_{i}.hex", bits=32)

        print(f"\nTest {i}:")
        print(f"  A = {A.tolist()}")
        print(f"  B = {B.tolist()}")
        print(f"  C = {C.tolist()}")

    # Also generate special test cases
    print("\nGenerating special test cases...")

    # Identity test
    A_id = np.arange(1, n*n + 1, dtype=np.int16).reshape(n, n)
    B_id = np.eye(n, dtype=np.int16)
    C_id = (A_id.astype(np.int64) @ B_id.astype(np.int64)).astype(np.int32)
    write_hex_file(A_id.astype(np.int32), output_dir / "mat_a_identity.hex", bits=32)
    write_hex_file(B_id.astype(np.int32), output_dir / "mat_b_identity.hex", bits=32)
    write_hex_file(C_id, output_dir / "mat_c_identity_expected.hex", bits=32)

    # Zero test
    A_zero = np.arange(1, n*n + 1, dtype=np.int16).reshape(n, n)
    B_zero = np.zeros((n, n), dtype=np.int16)
    C_zero = np.zeros((n, n), dtype=np.int32)
    write_hex_file(A_zero.astype(np.int32), output_dir / "mat_a_zero.hex", bits=32)
    write_hex_file(B_zero.astype(np.int32), output_dir / "mat_b_zero.hex", bits=32)
    write_hex_file(C_zero, output_dir / "mat_c_zero_expected.hex", bits=32)

    print(f"\nDone. Generated {num_tests + 2} test sets in {output_dir}")


def main():
    parser = argparse.ArgumentParser(description="Matrix Multiply Reference Model")
    parser.add_argument('--dim', type=int, default=4, help='Matrix dimension (default: 4)')
    parser.add_argument('--num-tests', type=int, default=5, help='Number of random tests (default: 5)')
    parser.add_argument('--seed', type=int, default=42, help='Random seed (default: 42)')
    parser.add_argument('--output-dir', type=str, default=None, help='Output directory')

    args = parser.parse_args()
    output_dir = Path(args.output_dir) if args.output_dir else None

    generate_test_vectors(n=args.dim, num_tests=args.num_tests,
                          seed=args.seed, output_dir=output_dir)


if __name__ == "__main__":
    main()
