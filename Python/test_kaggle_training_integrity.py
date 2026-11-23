import ast
import json
import unittest
from pathlib import Path
from typing import Tuple

import numpy as np


NOTEBOOK_PATH = Path(__file__).with_name("EA_Model_Training_Kaggle.ipynb")


class KaggleTrainingIntegrityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        notebook = json.loads(NOTEBOOK_PATH.read_text(encoding="utf-8"))
        cls.cells = {
            index: "".join(cell.get("source", []))
            for index, cell in enumerate(notebook["cells"])
            if cell.get("cell_type") == "code"
        }
        cls.all_code = "\n".join(cls.cells.values())

    @staticmethod
    def load_function(source, name, namespace):
        tree = ast.parse(source)
        definition = next(
            node for node in tree.body
            if isinstance(node, ast.FunctionDef) and node.name == name
        )
        exec(
            compile(ast.Module(body=[definition], type_ignores=[]), str(NOTEBOOK_PATH), "exec"),
            namespace,
        )
        return namespace[name]

    def test_feature_lags_do_not_wrap_future_rows(self):
        lag = self.load_function(self.cells[6], "_lag", {"np": np})
        np.testing.assert_array_equal(lag(np.array([4.0, 5.0, 6.0]), 1), [0.0, 4.0, 5.0])
        self.assertNotIn("np.roll(", self.all_code)

    def test_same_bar_double_touch_is_not_directionally_biased(self):
        label, label_ends = self.load_function(
            self.cells[8],
            "triple_barrier_labels",
            {"np": np, "Tuple": Tuple},
        )(
            close=np.array([100.0, 100.0, 100.0, 100.0]),
            high=np.array([100.0, 102.0, 100.0, 100.0]),
            low=np.array([100.0, 98.0, 100.0, 100.0]),
            atr=np.ones(4),
            k=1.0,
            vertical_bars=2,
        )
        self.assertEqual(int(label[0]), 0)
        self.assertEqual(int(label_ends[0]), 1)

    def test_sequence_features_label_return_and_time_share_event_index(self):
        prepare = self.load_function(self.cells[10], "prepare_sequences", {"np": np})
        features = np.arange(6, dtype=np.float32).reshape(6, 1)
        labels = np.array([-1, 0, 1, 1, 0, -1], dtype=np.int8)
        weights = np.array([1.0], dtype=np.float32)
        returns = np.array([0.04], dtype=np.float32)
        timestamps = np.arange(6)
        label_end_indices = np.array([0, 1, 2, 4, 5, 5])

        X, y, _, forward_return, event_time, end_time = prepare(
            features,
            labels,
            weights,
            returns,
            timestamps,
            label_end_indices,
            seq_len=3,
            sample_indices=np.array([3]),
        )

        np.testing.assert_array_equal(X[0, :, 0], [1.0, 2.0, 3.0])
        self.assertEqual(int(y[0]), 2)
        self.assertAlmostEqual(float(forward_return[0]), 0.04, places=6)
        self.assertEqual(int(event_time[0]), 3)
        self.assertEqual(int(end_time[0]), 4)

    def test_split_is_global_chronological_and_purges_cross_boundary_labels(self):
        source = self.cells[10]
        self.assertIn("chronological_order = np.argsort(timestamps_ns, kind=\"stable\")", source)
        self.assertIn("label_end_ns < train_cut", source)
        self.assertIn("label_end_ns < val_cut", source)
        self.assertIn("test_mask = timestamps_ns >= val_cut", source)

    def test_unvalidated_cpcv_cannot_pass_or_name_artifact_for_deployment(self):
        self.assertIn('cpcv_status = "not_run"', self.cells[18])
        self.assertIn("deploy_gate = False", self.cells[18])
        self.assertIn('"research_model_unvalidated.onnx"', self.cells[20])
        self.assertIn('"cpcv_psr": None', self.cells[20])
        self.assertIn('"deployment_artifact": deployment_artifact_name if deploy_gate else None', self.cells[20])

    def test_onnx_export_fails_on_opset_mismatch(self):
        source = self.cells[20]
        self.assertIn("dynamo=False", source)
        self.assertIn("if actual_opset != opset", source)
        self.assertIn("expected_opset=cfg.onnx_opset", source)

    def test_unsupported_patch_transformer_is_not_a_training_candidate(self):
        self.assertNotIn("PatchTST", self.cells[12])
        self.assertNotIn("PatchTST", self.cells[22])

    def test_holdout_report_is_after_export_and_not_part_of_selection_or_gate(self):
        self.assertNotIn("test_model", self.cells[16])
        self.assertNotIn("test_ic", self.cells[16])
        self.assertNotIn("test_metrics", self.cells[20])
        self.assertIn("timestamps_ns[train_mask | val_mask]", self.cells[18])
        self.assertIn("DEPLOYMENT GATE: FAIL (CPCV unavailable)", self.cells[18])
        self.assertIn("BACKTEST RESULTS (Test Set)", self.cells[24])
        self.assertNotIn("deploy_gate", self.cells[24])


if __name__ == "__main__":
    unittest.main()
