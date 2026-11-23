import unittest
from unittest.mock import patch

import numpy as np
import pandas as pd

from data_pipeline import (
    BASE_FEATURE_COUNT,
    build_dataset_splits,
    build_feature_matrix,
    compute_atr,
    prepare_sequences,
    triple_barrier_labels,
    triple_barrier_labels_with_ends,
)


class DataPipelineIntegrityTests(unittest.TestCase):
    def test_lag_features_do_not_wrap_from_final_bar(self):
        bar_count = 80
        index = np.arange(bar_count, dtype=np.float64)
        close = 100.0 + index * 0.03 + np.sin(index / 3.0)
        open_prices = close.copy()
        high = close + 0.2
        low = close - 0.2
        volume = 1000.0 + index

        original = build_feature_matrix(open_prices, high, low, close, volume)

        changed_close = close.copy()
        changed_close[-1] += 8.0
        changed_high = high.copy()
        changed_low = low.copy()
        changed_high[-1] = changed_close[-1] + 0.2
        changed_low[-1] = changed_close[-1] - 0.2
        changed = build_feature_matrix(
            open_prices, changed_high, changed_low, changed_close, volume
        )

        self.assertEqual(original.shape, (bar_count, BASE_FEATURE_COUNT))
        np.testing.assert_allclose(original[:-1], changed[:-1], rtol=0.0, atol=1e-7)

    def test_prepared_sequences_share_one_sample_index(self):
        features = np.arange(30, dtype=np.float32).reshape(10, 3)
        labels = np.array([-1, 0, 1, -1, 0, 1, -1, 0, 1, -1], dtype=np.int8)
        weights = np.array([0.25, 0.75], dtype=np.float32)
        returns = np.array([-0.125, 0.375], dtype=np.float32)
        timestamps = pd.date_range("2026-01-01", periods=10, freq="h").to_numpy()

        X, y, actual_weights, actual_returns, actual_timestamps, actual_end_timestamps = prepare_sequences(
            features,
            labels,
            weights,
            returns,
            timestamps,
            seq_len=3,
            sample_indices=[2, 5],
        )

        np.testing.assert_array_equal(X[0], features[0:3])
        np.testing.assert_array_equal(X[1], features[3:6])
        np.testing.assert_array_equal(y, [labels[2] + 1, labels[5] + 1])
        np.testing.assert_array_equal(actual_weights, weights)
        np.testing.assert_array_equal(actual_returns, returns)
        np.testing.assert_array_equal(actual_timestamps, timestamps[[2, 5]])
        np.testing.assert_array_equal(actual_end_timestamps, actual_timestamps)

    def test_triple_barrier_records_actual_resolution_bar(self):
        close = np.full(8, 100.0)
        high = np.full(8, 100.0)
        low = np.full(8, 100.0)
        atr = np.ones(8)
        high[1] = 102.0
        low[3] = 98.0

        labels, end_bars = triple_barrier_labels_with_ends(
            close, high, low, atr, k=1.0, vertical_bars=2
        )

        self.assertEqual(labels[0], 1)
        self.assertEqual(end_bars[0], 1)
        self.assertEqual(labels[1], -1)
        self.assertEqual(end_bars[1], 3)

        flat = np.full(8, 100.0)
        timeout_labels, timeout_ends = triple_barrier_labels_with_ends(
            flat, flat, flat, atr, k=1.0, vertical_bars=2
        )
        self.assertEqual(timeout_labels[2], 0)
        self.assertEqual(timeout_ends[2], 4)

    def test_dataset_splits_exclude_incomplete_vertical_horizons(self):
        bar_count = 200
        vertical_bars = 3
        seq_len = 4
        bar_indices = np.arange(bar_count, dtype=np.float64)
        close = 100.0 + 0.25 * bar_indices + 0.01 * np.sin(bar_indices)
        timestamps = pd.date_range("2026-01-01", periods=bar_count, freq="h")
        frame = pd.DataFrame(
            {
                "date": timestamps,
                "open": close,
                "high": close + 0.5,
                "low": close - 0.5,
                "close": close,
                "volume": 1000.0 + bar_indices,
                "feature_0": bar_indices,
            }
        )
        events = list(range(5, bar_count))

        with patch("data_pipeline.cusum_filter", return_value=events):
            train, val, test, _ = build_dataset_splits(
                frame,
                seq_len=seq_len,
                vertical_bars=vertical_bars,
                train_ratio=0.70,
                val_ratio=0.15,
            )

        expected_labels, expected_end_bars = triple_barrier_labels_with_ends(
            close,
            close + 0.5,
            close - 0.5,
            compute_atr(close + 0.5, close - 0.5, close, 14),
            vertical_bars=vertical_bars,
        )
        all_sample_bars = []
        for split in (train, val, test):
            X, y, _, returns, split_timestamps, split_label_end_timestamps = split
            for position, timestamp in enumerate(split_timestamps):
                sample_index = int(
                    (pd.Timestamp(timestamp) - timestamps[0]).total_seconds() // 3600
                )
                all_sample_bars.append(sample_index)
                np.testing.assert_array_equal(
                    X[position, :, 0],
                    bar_indices[sample_index - seq_len + 1 : sample_index + 1],
                )
                self.assertEqual(y[position], int(expected_labels[sample_index]) + 1)
                expected_return = (
                    close[sample_index + vertical_bars] - close[sample_index]
                ) / close[sample_index]
                self.assertAlmostEqual(float(returns[position]), expected_return, places=6)
                self.assertEqual(
                    pd.Timestamp(split_label_end_timestamps[position]),
                    timestamps[expected_end_bars[sample_index]],
                )

        self.assertEqual(max(all_sample_bars), bar_count - vertical_bars - 1)
        self.assertNotIn(bar_count - vertical_bars, all_sample_bars)
        self.assertNotIn(bar_count - 1, all_sample_bars)
        self.assertLess(max(pd.to_datetime(train[5])), min(pd.to_datetime(val[4])))
        self.assertLess(max(pd.to_datetime(val[5])), min(pd.to_datetime(test[4])))


if __name__ == "__main__":
    unittest.main()
