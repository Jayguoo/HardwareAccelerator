#!/usr/bin/env python3
"""
verify_results.py — Compare RTL output against expected results

Reads RTL-generated .hex result files and compares against expected
golden files from the reference model.

Usage:
    python verify_results.py [--test-dir DIR] [--num-tests N] [--dim N]
"""

import argparse
import sys
import numpy as np
from pathlib import Path
from matmul_reference import read_hex_file


def verify_single(result_file: Path, expected_file: Path,
                  shape: tuple, tolerance: int = 0) -> bool:
    """Compare a single result file against expected."""
    if not result_file.exists():
        print(f"  [SKIP] Result file not found: {result_file}")
        return None

    if not expected_file.exists():
        print(f"  [ERROR] Expected file not found: {expected_file}")
        return False

    result = read_hex_file(result_file, shape)
    expected = read_hex_file(expected_file, shape)

    mismatches = np.abs(result - expected) > tolerance
    num_mismatches = np.sum(mismatches)

    if num_mismatches > 0:
        print(f"  [FAIL] {num_mismatches} mismatches in {result_file.name}")
        # Show detailed mismatch info
        for i in range(shape[0]):
            for j in range(shape[1]):
                if mismatches[i, j]:
                    print(f"    C[{i}][{j}]: expected {expected[i,j]}, got {result[i,j]}")
        return False
    else:
        print(f"  [PASS] {result_file.name} — all {shape[0]*shape[1]} elements match")
        return True


def main():
    parser = argparse.ArgumentParser(description="Verify RTL results against reference")
    parser.add_argument('--test-dir', type=str, default=None, help='Test data directory')
    parser.add_argument('--num-tests', type=int, default=5, help='Number of random tests')
    parser.add_argument('--dim', type=int, default=4, help='Matrix dimension')
    parser.add_argument('--tolerance', type=int, default=0, help='Match tolerance')

    args = parser.parse_args()

    if args.test_dir:
        test_dir = Path(args.test_dir)
    else:
        test_dir = Path(__file__).parent.parent.parent / 'sim' / 'test_data'

    shape = (args.dim, args.dim)
    pass_count = 0
    fail_count = 0
    skip_count = 0

    print("=" * 50)
    print("  Matrix Multiply Verification")
    print(f"  Test directory: {test_dir}")
    print(f"  Matrix size: {args.dim}x{args.dim}")
    print("=" * 50)

    # Random tests
    for i in range(args.num_tests):
        result_file = test_dir / f"mat_c_result_{i}.hex"
        expected_file = test_dir / f"mat_c_expected_{i}.hex"

        print(f"\nTest {i}:")
        result = verify_single(result_file, expected_file, shape, args.tolerance)
        if result is True:
            pass_count += 1
        elif result is False:
            fail_count += 1
        else:
            skip_count += 1

    # Special tests
    for name in ['identity', 'zero']:
        result_file = test_dir / f"mat_c_{name}_result.hex"
        expected_file = test_dir / f"mat_c_{name}_expected.hex"

        print(f"\nTest ({name}):")
        result = verify_single(result_file, expected_file, shape, args.tolerance)
        if result is True:
            pass_count += 1
        elif result is False:
            fail_count += 1
        else:
            skip_count += 1

    # Summary
    total = pass_count + fail_count
    print("\n" + "=" * 50)
    print(f"  Results: {pass_count} PASS, {fail_count} FAIL, {skip_count} SKIP")
    if fail_count == 0 and pass_count > 0:
        print("  ALL TESTS PASSED")
    elif fail_count > 0:
        print("  SOME TESTS FAILED")
    print("=" * 50)

    sys.exit(0 if fail_count == 0 else 1)


if __name__ == "__main__":
    main()
