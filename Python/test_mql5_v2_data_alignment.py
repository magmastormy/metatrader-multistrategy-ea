import ast
import unittest
from itertools import combinations
from pathlib import Path
from typing import List

import numpy as np


def load_functions():
    source_path = Path(__file__).with_name('mql5_v2.py')
    tree = ast.parse(source_path.read_text(encoding='utf-8'))
    required = {
        'triple_barrier_labels_with_ends',
        '_safe_lag',
        'prepare_sequences',
        'purge_embargo',
        'cpcv_folds',
    }
    import pandas as pd

    namespace = {'np': np, 'pd': pd, 'List': List, 'combinations': combinations}
    for node in tree.body:
        if isinstance(node, ast.FunctionDef) and node.name in required and node.name not in namespace:
            exec(compile(ast.Module(body=[node], type_ignores=[]), str(source_path), 'exec'), namespace)
    missing = required.difference(namespace)
    if missing:
        raise AssertionError(f'Script functions not found: {sorted(missing)}')
    return namespace


class Mql5V2DataAlignmentTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.functions = load_functions()

    def test_barrier_tie_is_stop_first_and_tracks_resolution(self):
        close = np.full(6, 100.0)
        high = np.full(6, 100.0)
        low = np.full(6, 100.0)
        high[1] = 102.0
        low[1] = 98.0

        labels, ends = self.functions['triple_barrier_labels_with_ends'](
            close, high, low, np.ones(6), k=1.0, vertical_bars=2
        )

        self.assertEqual(labels[0], -1)
        self.assertEqual(ends[0], 1)

    def test_lag_never_wraps_future_rows_into_the_start(self):
        values = np.array([10.0, 20.0, 30.0])
        np.testing.assert_array_equal(self.functions['_safe_lag'](values, 1), [0.0, 10.0, 20.0])

    def test_sequence_records_actual_label_interval(self):
        features = np.arange(24, dtype=np.float32).reshape(8, 3)
        labels = np.array([0, 0, 0, 1, -1, 0, -1, 0], dtype=np.int8)
        weights = np.array([0.5, 0.7], dtype=np.float32)
        returns = np.array([0.01, -0.02], dtype=np.float32)
        timestamps = np.arange(8)

        X, y, _, _, starts, ends = self.functions['prepare_sequences'](
            features, labels, weights, returns, timestamps, 3, [3, 6], [4, 7]
        )

        np.testing.assert_array_equal(X[0], features[0:3])
        np.testing.assert_array_equal(X[1], features[3:6])
        np.testing.assert_array_equal(y, [labels[3] + 1, labels[6] + 1])
        np.testing.assert_array_equal(starts, [2, 5])
        np.testing.assert_array_equal(ends, [4, 7])

    def test_cpcv_groups_equal_timestamps_and_purges_overlap(self):
        starts = np.repeat(np.arange(6, dtype=np.int64) * 10, 2)
        folds = self.functions['cpcv_folds'](starts, starts.copy(), n_splits=3, n_test=1)
        for _, test_idx in folds:
            self.assertEqual(len(test_idx), 4)
            self.assertEqual(len(np.unique(starts[test_idx])), 2)

        interval_starts = np.array([0, 10, 100, 110], dtype=np.int64)
        interval_ends = np.array([4, 101, 105, 115], dtype=np.int64)
        kept = self.functions['purge_embargo'](
            np.array([0, 1, 3]), np.array([2]), interval_starts, interval_ends
        )
        np.testing.assert_array_equal(kept, [0, 3])


if __name__ == '__main__':
    unittest.main()
