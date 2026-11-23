import unittest
from pathlib import Path


SOURCE = (Path(__file__).resolve().parents[1] / "Strategies" / "NYOpenGapStrategy.mqh").read_text(
    encoding="utf-8", errors="replace"
)


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


class NYOpenGapDSTContractTests(unittest.TestCase):
    def test_transition_instants_are_utc_not_local_clock_hours(self):
        self.assertIn("dstStartStruct.hour = 7;", SOURCE)
        self.assertIn("dstEndStruct.hour = 6;", SOURCE)

    def test_dst_helper_compares_utc_input_to_utc_transition_bounds(self):
        helper = function_body(SOURCE, "bool NYOpenIsUSDaylightTime(const datetime when)")
        self.assertIn("when >= dstStart && when < dstEnd", helper)
        self.assertNotIn("TimeCurrent()", helper)
        self.assertNotIn("TimeGMT()", helper)

    def test_historical_broker_bar_mapping_fails_closed_on_offset_mismatch(self):
        self.assertIn("iTime(m_symbol, PERIOD_M30, openShift) != nyOpenServer", SOURCE)
        self.assertIn("iTime(m_symbol, PERIOD_M30, closeShift) != nyPriorCloseBarOpen", SOURCE)
