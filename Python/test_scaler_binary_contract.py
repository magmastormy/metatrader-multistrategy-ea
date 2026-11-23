import ast
import struct
import tempfile
import unittest
from pathlib import Path

import numpy as np
from sklearn.preprocessing import RobustScaler, StandardScaler

from data_pipeline import save_scaler_to_bin


class ScalerBinaryContractTests(unittest.TestCase):
    def assert_scaler_blob(self, path, expected_center, expected_scale):
        payload = path.read_bytes()
        feature_count = struct.unpack_from("<i", payload)[0]
        self.assertEqual(feature_count, len(expected_center))
        self.assertEqual(len(payload), 4 + feature_count * 16)
        center = np.frombuffer(payload, dtype="<f8", count=feature_count, offset=4)
        scale = np.frombuffer(
            payload, dtype="<f8", count=feature_count, offset=4 + feature_count * 8
        )
        np.testing.assert_allclose(center, expected_center)
        np.testing.assert_allclose(scale, expected_scale)

    def test_standard_scaler_export_matches_runtime_layout(self):
        scaler = StandardScaler().fit(np.array([[1.0, 10.0], [3.0, 14.0]]))
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "scaler.bin"
            save_scaler_to_bin(scaler, str(output))
            self.assert_scaler_blob(output, scaler.mean_, scaler.scale_)

    def test_robust_scaler_export_matches_runtime_layout(self):
        source_path = Path(__file__).with_name("mql5_v2.py")
        tree = ast.parse(source_path.read_text(encoding="utf-8"))
        serializer = next(
            node
            for node in tree.body
            if isinstance(node, ast.FunctionDef) and node.name == "save_scaler_to_bin"
        )
        namespace = {"Path": Path, "RobustScaler": RobustScaler, "struct": struct}
        exec(compile(ast.Module(body=[serializer], type_ignores=[]), str(source_path), "exec"), namespace)
        scaler = RobustScaler(quantile_range=(5.0, 95.0)).fit(
            np.array([[1.0, 10.0], [3.0, 14.0], [8.0, 20.0]])
        )
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "scaler.bin"
            namespace["save_scaler_to_bin"](scaler, str(output))
            self.assert_scaler_blob(output, scaler.center_, scaler.scale_)

    def test_runtime_requires_exact_width_and_fails_closed(self):
        root = Path(__file__).parents[1]
        scaler_source = (root / "Core/AI/PipelineScaler.mqh").read_text(encoding="utf-8")
        pipeline_source = (root / "Core/AI/FeaturePipelineONNX.mqh").read_text(encoding="utf-8")
        adapter_source = (root / "Core/Strategy/OnnxAIStrategyAdapter.mqh").read_text(encoding="utf-8")

        self.assertIn("featureCount != expectedFeatureCount", scaler_source)
        self.assertIn("ArraySize(features) != featureCount", scaler_source)
        self.assertIn("FileSize(handle) != 4 + (long)featureCount * 16", scaler_source)
        self.assertIn("if(!m_scaler.IsLoaded() || !m_scaler.Apply(features))", pipeline_source)
        self.assertNotIn("continue with unscaled features", pipeline_source)
        self.assertNotIn("CPipelineScaler m_scaler", adapter_source)

    def test_robust_trainer_uses_the_runtime_artifact_name_and_format(self):
        source = Path(__file__).with_name("mql5_v2.py").read_text(encoding="utf-8")
        self.assertIn("SCALER_OUTPUT = os.path.join(MODELS_DIR, 'scaler.bin')", source)
        self.assertIn("save_scaler_to_bin(scaler, scaler_output)", source)
        self.assertNotIn("scaler_v2.bin", source)
        self.assertNotIn("SCL2", source)


if __name__ == "__main__":
    unittest.main()
