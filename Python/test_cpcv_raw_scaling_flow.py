import json
import unittest
from pathlib import Path


class CpcvRawScalingFlowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.python_dir = Path(__file__).parent

    def test_standard_trainer_keeps_cpcv_features_raw(self):
        source = (self.python_dir / 'train_model.py').read_text(encoding='utf-8')

        self.assertIn('raw_train_split, raw_val_split, raw_test_split, annualization = build_dataset_splits(', source)
        self.assertIn('train_split, val_split, test_split, _ = _scale_splits(', source)
        self.assertIn('arrays = raw_train_split', source)
        self.assertNotIn('np.concatenate([raw_train_split[i], raw_val_split[i], raw_test_split[i]], axis=0)', source)
        self.assertNotIn('np.concatenate([train_split[i], val_split[i], test_split[i]]', source)

    def test_v2_cpcv_receives_raw_outer_training_features(self):
        source = (self.python_dir / 'mql5_v2.py').read_text(encoding='utf-8')

        self.assertIn('raw_train_split, raw_val_split, raw_test_split, annualization = build_dataset_splits(', source)
        self.assertIn('X=raw_train_split[0]', source)
        self.assertIn('fold_scaler.fit(X_train.reshape(-1, feature_count))', source)

    def test_notebook_cpcv_scaler_fits_raw_fold_features(self):
        notebook = json.loads((self.python_dir / 'Multi_Mt5_Colab_Notebook.ipynb').read_text(encoding='utf-8'))
        code = '\n'.join(''.join(cell.get('source', [])) for cell in notebook['cells'] if cell['cell_type'] == 'code')
        cpcv_code = ''.join(notebook['cells'][19].get('source', []))

        self.assertIn('raw_train_split, raw_val_split, raw_test_split, annualization = build_dataset_splits(', code)
        self.assertIn('fit_fold_feature_scaler(arrays_all[0], fit_idx)', code)
        self.assertIn('arrays_all = raw_train_split', cpcv_code)
        self.assertIn('label_end_timestamps=arrays_all[5]', cpcv_code)
        self.assertNotIn('raw_test_split', cpcv_code)
        self.assertNotIn('zip(train_split, val_split, test_split)', code)

    def test_generated_notebook_cpcv_uses_training_data_only(self):
        source = (self.python_dir / 'write_colab.py').read_text(encoding='utf-8')

        self.assertIn('raw_train_split, raw_val_split, raw_test_split, annualization = build_dataset_splits(', source)
        self.assertIn('arrays_all = raw_train_split', source)
        self.assertNotIn('zip(raw_train_split, raw_val_split, raw_test_split)', source)
        self.assertIn('fit_fold_feature_scaler(arrays_all[0], fit_idx)', source)
        self.assertNotIn('D:\\TraeProjects\\metatrader-multistrategy-ea', source)
        self.assertIn('Path(__file__).with_name("train_all_models_colab.ipynb")', source)

    def test_standalone_validator_uses_raw_features_and_fold_scaler_template(self):
        source = (self.python_dir / 'validate_model.py').read_text(encoding='utf-8')

        self.assertIn('from data_pipeline import build_dataset_splits', source)
        self.assertIn('"--fold-scaler-template"', source)
        self.assertIn('return model_path, joblib.load(scaler_path)', source)

    def test_feature_sources_do_not_use_circular_rolls(self):
        for filename in ('data_pipeline.py', 'mql5_v2.py', 'Multi_Mt5_Colab_Notebook.ipynb'):
            with self.subTest(filename=filename):
                source = (self.python_dir / filename).read_text(encoding='utf-8')
                self.assertNotIn('np.roll(', source)


if __name__ == '__main__':
    unittest.main()
