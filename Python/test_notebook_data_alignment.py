import ast
import json
import unittest
from pathlib import Path
from typing import List

import numpy as np
from sklearn.preprocessing import StandardScaler


def load_notebook_functions():
    notebook_path = Path(__file__).with_name('Multi_Mt5_Colab_Notebook.ipynb')
    notebook = json.loads(notebook_path.read_text(encoding='utf-8'))
    required = {
        'triple_barrier_labels_with_ends',
        '_lag',
        'prepare_sequences',
        '_split_arrays',
        'purged_time_split_indices',
        'fit_fold_feature_scaler',
        'transform_fold_features',
    }
    functions = {}
    for cell in notebook['cells']:
        if cell['cell_type'] != 'code':
            continue
        source = ''.join(cell['source'])
        try:
            tree = ast.parse(source)
        except SyntaxError:
            continue
        definitions = [
            node for node in tree.body
            if isinstance(node, ast.FunctionDef) and node.name in required
        ]
        for definition in definitions:
            namespace = {'np': np, 'List': List, 'StandardScaler': StandardScaler}
            exec(compile(ast.Module(body=[definition], type_ignores=[]), str(notebook_path), 'exec'), namespace)
            functions[definition.name] = namespace[definition.name]
    missing = required.difference(functions)
    if missing:
        raise AssertionError(f'Notebook functions not found: {sorted(missing)}')
    return functions


class NotebookDataAlignmentTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.functions = load_notebook_functions()

    def test_barrier_tie_is_stop_first_and_tracks_resolution(self):
        close = np.full(6, 100.0)
        high = np.full(6, 100.0)
        low = np.full(6, 100.0)
        high[1] = 102.0
        low[1] = 98.0
        atr = np.ones(6)

        labels, ends = self.functions['triple_barrier_labels_with_ends'](
            close, high, low, atr, k=1.0, vertical_bars=2
        )

        self.assertEqual(labels[0], -1)
        self.assertEqual(ends[0], 1)

    def test_lag_never_wraps_future_rows_into_the_start(self):
        values = np.array([10.0, 20.0, 30.0])
        np.testing.assert_array_equal(self.functions['_lag'](values, 1), [0.0, 10.0, 20.0])

    def test_sequences_keep_sample_and_label_end_timestamps_aligned(self):
        features = np.arange(24, dtype=np.float32).reshape(8, 3)
        labels = np.array([0, 0, 0, 1, -1, 0, -1, 0], dtype=np.int8)
        weights = np.array([0.5, 0.7], dtype=np.float32)
        returns = np.array([0.01, -0.02], dtype=np.float32)
        timestamps = np.arange(8)

        X, y, actual_weights, actual_returns, starts, ends = self.functions['prepare_sequences'](
            features, labels, weights, returns, timestamps, 3, [2, 5], [3, 7]
        )

        np.testing.assert_array_equal(X[0], features[0:3])
        np.testing.assert_array_equal(X[1], features[3:6])
        np.testing.assert_array_equal(y, [labels[2] + 1, labels[5] + 1])
        np.testing.assert_array_equal(actual_weights, weights)
        np.testing.assert_array_equal(actual_returns, returns)
        np.testing.assert_array_equal(starts, [2, 5])
        np.testing.assert_array_equal(ends, [3, 7])

    def test_ratio_split_purges_actual_label_end_across_boundaries(self):
        n = 60
        features = np.arange(n, dtype=np.float32).reshape(n, 1, 1)
        labels = np.zeros(n, dtype=np.int64)
        weights = np.ones(n, dtype=np.float32)
        returns = np.zeros(n, dtype=np.float32)
        timestamps = np.arange(n)
        label_bars = np.arange(n, dtype=np.int64) + 100
        label_end_bars = label_bars.copy()
        label_end_bars[41] = label_bars[42]
        label_end_bars[53] = label_bars[54]

        train, val, test = self.functions['_split_arrays'](
            features, labels, weights, returns, timestamps, timestamps,
            label_bars, label_end_bars, 0.70, 0.15
        )

        self.assertNotIn(41, train[0][:, 0, 0])
        self.assertNotIn(53, val[0][:, 0, 0])
        self.assertEqual(len(train), 6)
        self.assertEqual(len(val), 6)
        self.assertEqual(len(test), 6)

    def test_nested_split_and_scaler_use_fit_timestamps_only(self):
        timestamps = np.array([40, 0, 70, 20, 60, 10, 50, 30], dtype='datetime64[s]')
        label_ends = timestamps.copy()
        label_ends[6] = np.datetime64('1970-01-01T00:01:00')
        fit_idx, val_idx = self.functions['purged_time_split_indices'](
            np.arange(len(timestamps)), timestamps, label_ends, validation_ratio=0.25
        )
        self.assertTrue(np.all(label_ends[fit_idx] < min(timestamps[val_idx])))

        features = np.array([[[0.0]], [[2.0]], [[1000.0]]], dtype=np.float32)
        scaler = self.functions['fit_fold_feature_scaler'](features, np.array([0, 1]))
        transformed = self.functions['transform_fold_features'](features[[2]], scaler)
        self.assertEqual(float(scaler.mean_[0]), 1.0)
        self.assertGreater(float(transformed[0, 0, 0]), 100.0)


if __name__ == '__main__':
    unittest.main()
