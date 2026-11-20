import ast
import unittest
from pathlib import Path


class Mql5V2SetupSafetyTests(unittest.TestCase):
    def test_dependency_install_is_opt_in_and_uses_argument_list(self):
        source_path = Path(__file__).with_name("mql5_v2.py")
        tree = ast.parse(source_path.read_text(encoding="utf-8"))
        install_calls = [
            node
            for node in ast.walk(tree)
            if isinstance(node, ast.Call)
            and isinstance(node.func, ast.Attribute)
            and node.func.attr == "check_call"
        ]

        self.assertEqual(len(install_calls), 1)
        installer = next(
            node
            for node in tree.body
            if isinstance(node, ast.FunctionDef) and node.name == "install_dependencies"
        )
        self.assertIn(install_calls[0], ast.walk(installer))
        self.assertTrue(
            any(
                isinstance(node, ast.If)
                and isinstance(node.test, ast.BoolOp)
                and any(
                    isinstance(value, ast.Compare)
                    and isinstance(value.left, ast.Name)
                    and value.left.id == "__name__"
                    for value in node.test.values
                )
                and any(
                    isinstance(child, ast.Call)
                    and isinstance(child.func, ast.Name)
                    and child.func.id == "install_dependencies"
                    for child in ast.walk(node)
                )
                for node in tree.body
            )
        )
        self.assertIsInstance(install_calls[0].args[0], ast.BinOp)


if __name__ == "__main__":
    unittest.main()
