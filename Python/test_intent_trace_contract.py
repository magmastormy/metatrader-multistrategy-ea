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


class IntentTraceContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.trace = (ROOT / "Core" / "Utils" / "IntentTrace.mqh").read_text(encoding="utf-8")
        cls.signals = (ROOT / "Core" / "Orchestration" / "SignalGenerator.mqh").read_text(encoding="utf-8")
        cls.consensus = (ROOT / "Core" / "Management" / "ConsensusEngine.mqh").read_text(encoding="utf-8")
        cls.enterprise_manager = (ROOT / "Core" / "Management" / "EnterpriseStrategyManager.mqh").read_text(encoding="utf-8")
        cls.position_lifecycle = (ROOT / "Core" / "Management" / "PositionLifecycleManager.mqh").read_text(encoding="utf-8")
        cls.training_exporter = (ROOT / "TrainingDataExporter.mq5").read_text(encoding="utf-8")
        cls.candidate = (ROOT / "Core" / "Orchestration" / "CandidateBuilder.mqh").read_text(encoding="utf-8")
        cls.orchestrator = (ROOT / "Core" / "Orchestration" / "EAOrchestrator.mqh").read_text(encoding="utf-8")
        cls.executor = (ROOT / "Core" / "Orchestration" / "TradeExecutor.mqh").read_text(encoding="utf-8")
        cls.trade_manager = (ROOT / "Core" / "Trading" / "TradeManager.mqh").read_text(encoding="utf-8")
        cls.position_store = (ROOT / "Core" / "Position" / "PositionMgrStateStore.mqh").read_text(encoding="utf-8")

    def test_id_uses_replay_stable_symbol_bar_and_timeframe(self):
        build_id = function_body(self.trace, "static string BuildId(")
        self.assertIn('if(symbol == "" || eventTime <= 0 || scope == "")', build_id)
        self.assertIn('StringFormat("INT-%d-%I64d-%s-%s-%s", (int)timeframe, (long)eventTime, modeCode, scope, symbol)', build_id)

    def test_all_consensus_callers_supply_scoped_ids(self):
        self.assertIn('"LIFECYCLE");', self.position_lifecycle)
        self.assertIn("EVAL_MODE_INTRABAR, lifecycleIntentId);", self.position_lifecycle)
        self.assertIn('"TRAINING");', self.training_exporter)
        self.assertIn("EVAL_MODE_NEW_BAR, trainingIntentId);", self.training_exporter)
        self.assertNotIn('const string intentId = ""', self.consensus)
        self.assertNotIn('const string intentId = ""', self.enterprise_manager)

    def test_consensus_events_and_signal_result_share_the_id(self):
        self.assertIn("BuildId(symbol, decisionBarTime", self.signals)
        self.assertIn("evalMode, intentId);", self.signals)
        self.assertIn("results[managerIdx].intentId = intentId;", self.signals)
        self.assertIn("| intent_id=%s", self.consensus)
        self.assertIn("intentTag);", self.consensus)

    def test_post_consensus_rejections_keep_specific_reasons(self):
        build_candidate = function_body(self.candidate, "bool BuildCandidate(")
        self.assertIn("candidate.intentId = intentId;", build_candidate)
        self.assertIn("RejectCandidate(candidate, riskResult.message)", build_candidate)
        self.assertIn('"POST_CONSENSUS"', self.orchestrator)
        self.assertIn("validation.vetoReason", self.orchestrator)
        self.assertIn("candidate.failureReason", self.orchestrator)

    def test_execution_receipt_is_joinable_to_its_intent(self):
        self.assertIn("newBarSignals[i].intentId", self.orchestrator)
        self.assertIn("candidate.intentId", self.executor)
        self.assertIn("| order=%I64u | deal=%I64u | intent_id=%s", self.trade_manager)
        self.assertIn('"EXECUTION",', self.orchestrator)
        self.assertIn("UpsertIntentPositionMap((ulong)provPosId, candidate.intentId)", self.orchestrator)
        self.assertIn("GetPendingCloseProfits(positionIds, profits, predictionIds, intentIds)", self.orchestrator)
        self.assertIn("[INTENT-OUTCOME]", self.orchestrator)
        self.assertIn("string intentId;", self.position_store)
        self.assertIn("RemovePositionIntentId", self.position_store)


if __name__ == "__main__":
    unittest.main()
