import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def function_body(source: str, signature: str) -> str:
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 0
    for position in range(opening, len(source)):
        if source[position] == "{":
            depth += 1
        elif source[position] == "}":
            depth -= 1
            if depth == 0:
                return source[opening + 1 : position]
    raise AssertionError(f"Unclosed function body: {signature}")


class ClosedBarSignalContractTests(unittest.TestCase):
    def test_isp_compares_last_closed_bar_with_prior_consolidation(self):
        source = (ROOT / "Strategies" / "UnifiedICTFiles" / "MarketStructureAnalyzer.mqh").read_text(encoding="utf-8")
        body = function_body(source, "bool CMarketStructureAnalyzer::IdentifyISP(")

        self.assertIn("Bars(m_symbol, m_timeframe) < 22", body)
        self.assertIn("for(int i = 2; i <= 21; i++)", body)
        self.assertIn("iHigh(m_symbol, m_timeframe, 1)", body)
        self.assertIn("iLow(m_symbol, m_timeframe, 1)", body)
        self.assertNotIn("iHigh(m_symbol, m_timeframe, 0)", body)
        self.assertNotIn("iLow(m_symbol, m_timeframe, 0)", body)

    def test_support_resistance_touch_count_excludes_forming_bar(self):
        source = (ROOT / "Strategies" / "SupportResistanceFiles" / "SupportResistanceDetector.mqh").read_text(encoding="utf-8")
        body = function_body(source, "void CSupportResistanceDetector::UpdateTouches(")

        self.assertIn("CopyRates(m_symbol, m_timeframe, 1, 100, rates)", body)
        self.assertNotIn("CopyRates(m_symbol, m_timeframe, 0,", body)


if __name__ == "__main__":
    unittest.main()
