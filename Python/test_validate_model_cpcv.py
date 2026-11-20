import unittest
from types import SimpleNamespace
from unittest.mock import patch

import numpy as np
import validate_model

from validate_model import (
    cpcv_folds,
    fit_fold_feature_scaler,
    purge_embargo,
    purged_time_split_indices,
    run_cpcv,
    transform_fold_features,
)


class CpcvLabelIntervalTests(unittest.TestCase):
    def test_irregular_bar_gaps_use_actual_label_intervals(self):
        starts = np.array([0, 10, 100, 110], dtype=np.int64)
        ends = np.array([4, 15, 105, 115], dtype=np.int64)

        kept = purge_embargo(
            train_idx=np.array([0, 1, 3]),
            test_idx=np.array([2]),
            starts_ns=starts,
            label_ends_ns=ends,
        )

        np.testing.assert_array_equal(kept, [0, 1, 3])

    def test_overlapping_actual_label_span_is_purged(self):
        starts = np.array([0, 10, 100, 110], dtype=np.int64)
        ends = np.array([4, 101, 105, 115], dtype=np.int64)

        kept = purge_embargo(
            train_idx=np.array([0, 1, 3]),
            test_idx=np.array([2]),
            starts_ns=starts,
            label_ends_ns=ends,
        )

        np.testing.assert_array_equal(kept, [0, 3])

    def test_same_timestamp_rows_stay_in_one_fold(self):
        starts = np.repeat(np.arange(6, dtype=np.int64) * 10, 2)
        ends = starts.copy()
        folds = cpcv_folds(starts, ends, n_splits=3, n_test=1)

        self.assertEqual(len(folds), 3)
        for _, test_idx in folds:
            self.assertEqual(len(np.unique(starts[test_idx])), 2)
            self.assertEqual(len(test_idx), 4)

    def test_cpcv_folds_follow_time_not_input_row_order(self):
        starts = np.array([50, 0, 50, 0, 100, 100], dtype=np.int64)
        ends = starts.copy()
        folds = cpcv_folds(starts, ends, n_splits=3, n_test=1)

        self.assertEqual(len(folds), 3)
        test_times = [np.unique(starts[test_idx]).tolist() for _, test_idx in folds]
        self.assertEqual(test_times, [[0], [50], [100]])

    def test_nested_validation_split_is_chronological_and_purged(self):
        timestamps = np.array([40, 0, 70, 20, 60, 10, 50, 30], dtype='datetime64[s]')
        label_ends = timestamps.copy()
        label_ends[6] = np.datetime64('1970-01-01T00:01:00')
        fit_idx, validation_idx = purged_time_split_indices(
            np.arange(len(timestamps)), timestamps, label_ends, validation_ratio=0.25
        )

        self.assertLess(max(timestamps[fit_idx]), min(timestamps[validation_idx]))
        self.assertTrue(np.all(label_ends[fit_idx] < min(timestamps[validation_idx])))

    def test_fold_scaler_fits_only_cpcv_fit_rows(self):
        features = np.array([[[0.0]], [[2.0]], [[1000.0]]], dtype=np.float32)
        scaler = fit_fold_feature_scaler(features, np.array([0, 1]))
        transformed_test = transform_fold_features(features[[2]], scaler)

        self.assertEqual(float(scaler.mean_[0]), 1.0)
        self.assertGreater(float(transformed_test[0, 0, 0]), 100.0)

    def test_run_cpcv_applies_each_fold_scaler_to_test_features(self):
        features = np.arange(18, dtype=np.float32).reshape(9, 1, 2) * 100.0
        timestamps = np.arange(9).astype('datetime64[s]')
        returns = np.full(9, 0.01, dtype=np.float32)
        folds = cpcv_folds(timestamps.astype(np.int64), timestamps.astype(np.int64), n_splits=3)
        scalers = []
        captured_features = []

        class FakeSession:
            def get_inputs(self):
                return [SimpleNamespace(name='features')]

            def run(self, _outputs, feed):
                batch = feed['features']
                captured_features.append(batch.copy())
                logits = np.zeros((len(batch), 3), dtype=np.float32)
                logits[:, 1] = 1.0
                return [logits]

        fake_ort = SimpleNamespace(InferenceSession=lambda _path: FakeSession())

        def model_artifact(fold, train_idx):
            scaler = fit_fold_feature_scaler(features, train_idx)
            scalers.append(scaler)
            return f'fold-{fold}.onnx', scaler

        with patch.object(validate_model, 'ort', fake_ort):
            run_cpcv(
                X=features,
                bar_returns=returns,
                timestamps=timestamps,
                label_end_timestamps=timestamps,
                fold_model_path=model_artifact,
                n_splits=3,
                annualization=1.0,
            )

        self.assertEqual(len(folds), len(captured_features))
        self.assertEqual(len(folds), len(scalers))
        for (_, test_idx), scaler, captured in zip(folds, scalers, captured_features):
            expected = transform_fold_features(features[test_idx], scaler)
            np.testing.assert_allclose(captured, expected)


if __name__ == "__main__":
    unittest.main()
