import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class RunWindowContractTests(unittest.TestCase):
    def test_agent_port_is_checked_before_cold_state_reset(self):
        source = (ROOT / "Tools" / "run_window.ps1").read_text(encoding="utf-8")
        port_check = source.index("Get-NetTCPConnection -LocalPort 3000 -State Listen")
        cold_reset = source.index("if ($Cold) {")
        self.assertLess(port_check, cold_reset)
        self.assertIn("refusing to reset state or launch a backtest", source)


if __name__ == "__main__":
    unittest.main()
