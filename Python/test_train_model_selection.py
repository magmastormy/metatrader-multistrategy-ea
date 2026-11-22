import ast
import json
import unittest
from pathlib import Path


class TrainModelSelectionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source_path = Path(__file__).with_name("train_model.py")
        cls.tree = ast.parse(source_path.read_text(encoding="utf-8"))
        cls.functions = {
            node.name: node
            for node in cls.tree.body
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
        }

    def test_candidate_training_only_uses_validation_metrics(self):
        candidate = self.functions["train_candidate"]
        argument_names = [argument.arg for argument in candidate.args.args]
        self.assertNotIn("test_split", argument_names)

        metric_calls = [
            node
            for node in ast.walk(candidate)
            if isinstance(node, ast.Call)
            and isinstance(node.func, ast.Name)
            and node.func.id == "compute_ic"
        ]
        self.assertEqual(len(metric_calls), 1)
        self.assertEqual(metric_calls[0].args[1].id, "val_loader")

    def test_holdout_is_evaluated_once_after_validation_selection(self):
        main = self.functions["main"]
        holdout_calls = [
            node
            for node in ast.walk(main)
            if isinstance(node, ast.Call)
            and isinstance(node.func, ast.Name)
            and node.func.id == "compute_ic"
        ]
        self.assertEqual(len(holdout_calls), 1)
        self.assertEqual(holdout_calls[0].args[0].id, "best_model")
        self.assertEqual(holdout_calls[0].args[1].id, "test_loader")

        validation_selection = next(
            node
            for node in ast.walk(main)
            if isinstance(node, ast.If)
            and isinstance(node.test, ast.Compare)
            and isinstance(node.test.left, ast.Name)
            and node.test.left.id == "val_ic"
            and isinstance(node.test.comparators[0], ast.Name)
            and node.test.comparators[0].id == "best_val_ic"
        )
        self.assertLess(validation_selection.lineno, holdout_calls[0].lineno)

    def test_standard_deployment_gate_and_cpcv_exclude_holdout(self):
        source = Path(__file__).with_name("train_model.py").read_text(encoding="utf-8")
        self.assertIn("arrays = raw_train_split", source)
        self.assertIn('deploy_ok = best_val_ic >= args.min_val_ic and cpcv["deploy_gate"]', source)
        self.assertNotIn("deploy_ok = best_test_ic", source)

    def test_standalone_deployment_and_tree_baseline_use_validation(self):
        source = Path(__file__).with_name("mql5_v2.py").read_text(encoding="utf-8")
        self.assertIn("X=raw_train_split[0]", source)
        self.assertIn("deploy_ok = (best_val_ic >= CFG.MIN_IC_THRESHOLD)", source)
        self.assertIn("def train_lightgbm(train_split, val_split, metadata,", source)
        self.assertIn("preds = model.predict(X_va)", source)
        self.assertNotIn("X_te = test_split[0]", source)

    def test_legacy_notebook_candidates_and_cpcv_exclude_holdout(self):
        path = Path(__file__).with_name("Multi_Mt5_Colab_Notebook.ipynb")
        notebook = json.loads(path.read_text(encoding="utf-8"))
        candidate_cell = next(
            cell for cell in notebook["cells"]
            if "def train_candidate(" in "".join(cell.get("source", []))
        )
        candidate_source = "".join(candidate_cell["source"]).split("def train_candidate(", 1)[1].split("def train_lightgbm(", 1)[0]
        cpcv_source = "".join(notebook["cells"][19].get("source", []))
        code = "\n".join(
            "".join(cell.get("source", []))
            for cell in notebook["cells"]
            if cell.get("cell_type") == "code"
        )

        self.assertNotIn("test_split", candidate_source)
        self.assertNotIn("test_loader", candidate_source)
        self.assertNotIn("test_ic", code)
        self.assertIn("arrays_all = raw_train_split", cpcv_source)
        self.assertNotIn("raw_test_split", cpcv_source)
        self.assertIn("deploy_ok = best_val_ic >= min_ic_threshold", cpcv_source)

    def test_kaggle_notebook_keeps_holdout_out_of_selection_and_gate(self):
        notebook_path = Path(__file__).with_name("EA_Model_Training_Kaggle.ipynb")
        notebook = json.loads(notebook_path.read_text(encoding="utf-8"))
        cells = [
            "".join(cell.get("source", []))
            for cell in notebook["cells"]
            if cell.get("cell_type") == "code"
        ]
        selection_cell = next(cell for cell in cells if "# --- Select best model ---" in cell)
        gate_cell = next(cell for cell in cells if "DEPLOYMENT GATE: FAIL (CPCV unavailable)" in cell)
        metadata_cell = next(cell for cell in cells if "val_f1_macro" in cell and "cpcv_status" in cell)
        holdout_report = next(cell for cell in cells if "BACKTEST RESULTS (Test Set)" in cell)

        self.assertNotIn("test_loader", selection_cell)
        self.assertNotIn("test_ic", selection_cell)
        self.assertIn("deploy_gate = False", gate_cell)
        self.assertIn("timestamps_ns[train_mask | val_mask]", gate_cell)
        self.assertNotIn("test_ic", metadata_cell)
        self.assertNotIn("test_metrics", metadata_cell)
        self.assertIn("test_loader", holdout_report)
        self.assertNotIn("deploy_gate", holdout_report)
        self.assertLess(cells.index(metadata_cell), cells.index(holdout_report))

    def test_standalone_candidate_training_never_reads_holdout(self):
        source_path = Path(__file__).with_name("mql5_v2.py")
        tree = ast.parse(source_path.read_text(encoding="utf-8"))
        candidate = next(
            node
            for node in tree.body
            if isinstance(node, ast.FunctionDef) and node.name == "train_candidate"
        )
        argument_names = [argument.arg for argument in candidate.args.args]
        self.assertNotIn("test_split", argument_names)

        metric_calls = [
            node
            for node in ast.walk(candidate)
            if isinstance(node, ast.Call)
            and isinstance(node.func, ast.Name)
            and node.func.id == "compute_ic"
        ]
        self.assertEqual(len(metric_calls), 1)
        self.assertEqual(metric_calls[0].args[1].id, "val_loader")

    def test_standalone_holdout_is_scored_once_for_selected_model(self):
        source_path = Path(__file__).with_name("mql5_v2.py")
        tree = ast.parse(source_path.read_text(encoding="utf-8"))
        executable_statements = [
            node
            for node in tree.body
            if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef))
        ]
        holdout_calls = [
            node
            for statement in executable_statements
            for node in ast.walk(statement)
            if isinstance(node, ast.Call)
            and isinstance(node.func, ast.Name)
            and node.func.id == "compute_ic"
        ]
        self.assertEqual(len(holdout_calls), 1)
        self.assertEqual(holdout_calls[0].args[0].id, "best_model")
        self.assertEqual(holdout_calls[0].args[1].id, "test_loader")

    def test_colab_generator_keeps_holdout_out_of_pytorch_candidates_and_cpcv(self):
        source_path = Path(__file__).with_name("write_colab.py")
        tree = ast.parse(source_path.read_text(encoding="utf-8"))
        notebook_assignment = next(
            node
            for node in tree.body
            if isinstance(node, ast.Assign)
            and any(isinstance(target, ast.Name) and target.id == "notebook" for target in node.targets)
        )
        notebook = ast.literal_eval(notebook_assignment.value)
        cell = next(
            cell
            for cell in notebook["cells"]
            if "def train_candidate_amp" in "".join(cell.get("source", []))
        )
        cell_source = "".join(cell["source"])
        candidate_source = cell_source.split("    def train_candidate_amp", 1)[1].split("    results = {}", 1)[0]
        cpcv_source = cell_source.split("        X_all = raw_train_split[0]", 1)[1].split("        ok = val_ic", 1)[0]

        self.assertNotIn("test_split", candidate_source)
        self.assertNotIn("test_loader", candidate_source)
        self.assertNotIn("raw_val_split", cpcv_source)
        self.assertNotIn("raw_test_split", cpcv_source)
        self.assertIn("ok = val_ic >= cfg.min_val_ic", cell_source)

        generated_path = Path(__file__).with_name("train_all_models_colab.ipynb")
        generated_notebook = json.loads(generated_path.read_text(encoding="utf-8"))
        generated_cell = next(
            cell
            for cell in generated_notebook["cells"]
            if "def train_candidate_amp" in "".join(cell.get("source", []))
        )
        generated_source = "".join(generated_cell["source"])
        self.assertNotIn("test_loader = build_loader(test_split", generated_source)
        self.assertIn("X_all = raw_train_split[0]", generated_source)
        self.assertNotIn("X_all = np.concatenate([raw_train_split[0], raw_val_split[0], raw_test_split[0]])", generated_source)

        all_generated_code = "\n".join(
            "".join(cell.get("source", []))
            for cell in generated_notebook["cells"]
            if cell.get("cell_type") == "code"
        )
        self.assertNotIn("test_ic", all_generated_code)
        self.assertNotIn("X_te", all_generated_code)
        self.assertNotIn("r_te", all_generated_code)


if __name__ == "__main__":
    unittest.main()
