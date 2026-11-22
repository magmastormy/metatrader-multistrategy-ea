import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PIPELINE_PATH = ROOT / "Core" / "Risk" / "RiskValidationPipeline.mqh"
MARGIN_HEALTH_PATH = ROOT / "Core" / "Risk" / "RiskMarginHealth.mqh"
GRID_EXECUTION_PATH = ROOT / "Core" / "Scalp" / "GridRecoveryExecution.mqh"
GRID_ENGINE_PATH = ROOT / "Core" / "Scalp" / "GridRecoveryEngine.mqh"
TRADE_MANAGER_PATH = ROOT / "Core" / "Trading" / "TradeManager.mqh"


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


class RiskMarginCheckContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pipeline = PIPELINE_PATH.read_text(encoding="utf-8")
        cls.margin_health = MARGIN_HEALTH_PATH.read_text(encoding="utf-8")
        cls.grid_execution = GRID_EXECUTION_PATH.read_text(encoding="utf-8")
        cls.grid_engine = GRID_ENGINE_PATH.read_text(encoding="utf-8")
        cls.trade_manager = TRADE_MANAGER_PATH.read_text(encoding="utf-8")
        cls.validation_body = function_body(
            cls.pipeline,
            "bool CRiskValidationPipeline::ValidateMarginRequirements(",
        )
        cls.run_body = function_body(
            cls.pipeline,
            "SValidationResult CRiskValidationPipeline::Run(",
        )
        cls.margin_health_body = function_body(
            cls.margin_health,
            "bool CheckFreeMarginAndLevel(",
        )

    def test_broker_order_check_uses_candidate_market_request(self):
        for expression in (
            "marginRequest.action = TRADE_ACTION_DEAL",
            "marginRequest.volume = request.lotSize",
            "marginRequest.type = request.orderType",
            "marginRequest.type_filling = fillingMode",
            "OrderCheck(marginRequest, marginCheck)",
        ):
            with self.subTest(expression=expression):
                self.assertIn(expression, self.validation_body)

    def test_missing_quotes_and_failed_broker_checks_reject(self):
        self.assertIn("SymbolInfoTick(request.symbol, currentTick)", self.validation_body)
        self.assertIn("!MathIsValidNumber(currentTick.bid) || !MathIsValidNumber(currentTick.ask)", self.validation_body)
        self.assertIn("currentTick.bid <= 0.0 || currentTick.ask <= 0.0", self.validation_body)
        self.assertIn("!orderCheckPassed || marginCheck.retcode != 0", self.validation_body)
        self.assertIn("!MathIsValidNumber(marginCheck.margin_free)", self.validation_body)
        self.assertIn("marginCheck.margin > 0.0 && marginCheck.margin_level <= 0.0", self.validation_body)

    def test_netting_projection_is_not_manually_approximated(self):
        self.assertNotIn("OrderCalcMargin(", self.validation_body)
        self.assertNotIn("PositionsTotal()", self.validation_body)
        self.assertIn("marginCheck.margin_free", self.validation_body)
        self.assertIn("marginCheck.margin_level", self.validation_body)

    def test_margin_health_uses_broker_projected_level(self):
        self.assertIn("const double projectedMarginLevel", self.margin_health)
        self.assertIn("projectedFreeMargin < minimumProjectedFreeMargin", self.margin_health_body)
        self.assertIn("projectedMarginLevel < m_minMarginLevel", self.margin_health_body)
        self.assertNotIn("equity / projectedMargin", self.margin_health_body)

    def test_cold_start_budget_uses_only_ea_owned_positions(self):
        count_start = self.pipeline.index("int openPositionCount = 0;")
        count_end = self.pipeline.index("bool isColdStart", count_start)
        count_logic = self.pipeline[count_start:count_end]
        self.assertIn("IsMagicOwned(PositionGetInteger(POSITION_MAGIC))", count_logic)
        self.assertNotIn("int openPositionCount = PositionsTotal()", count_logic)

    def test_grid_recovery_uses_shared_execution_for_entry_and_close(self):
        entry_body = function_body(
            self.grid_execution,
            "bool ExecuteEntry(",
        )
        close_body = function_body(
            self.grid_execution,
            "bool ClosePositionTicket(",
        )

        self.assertIn("if(m_tradeManager == NULL)", entry_body)
        self.assertIn("m_tradeManager.OpenPosition(", entry_body)
        self.assertIn("m_tradeManager.GetLastExecutionReceipt(receipt)", entry_body)
        self.assertIn("if(m_tradeManager == NULL)", close_body)
        self.assertIn("m_tradeManager.ClosePosition(ticket", close_body)
        self.assertNotIn("CTrade ", entry_body)
        self.assertNotIn("CTrade ", close_body)
        self.assertIn("GetDynamicSlippage(symbolName)", self.trade_manager)
        self.assertNotIn("SetDeviationInPoints(50)", self.grid_execution)

    def test_close_requires_position_reconciliation_before_release(self):
        close_body = function_body(self.trade_manager, "bool CTradeManager::ClosePosition(")
        request_index = close_body.index("symbolTrade.PositionClose(ticket)")
        verify_index = close_body.index("if(PositionSelectByTicket(ticket))", request_index)
        release_index = close_body.index("RemoveEAOwnedPosition(ticket)")

        self.assertLess(request_index, verify_index)
        self.assertLess(verify_index, release_index)
        self.assertIn("GetDynamicSlippage(localSymbol)", close_body)
        self.assertIn("m_lastTradeResult = closeResult", close_body)

    def test_candidate_lot_is_step_valid_before_final_risk_gate(self):
        source = (ROOT / 'Core' / 'Orchestration' / 'CandidateBuilder.mqh').read_text(encoding='utf-8')
        body = function_body(source, 'bool BuildCandidate(')
        self.assertIn('SYMBOL_VOLUME_MIN', body)
        self.assertIn('SYMBOL_VOLUME_MAX', body)
        self.assertIn('SYMBOL_VOLUME_STEP', body)
        self.assertIn('MathIsValidNumber(volumeStep) && volumeStep > 0.0', body)
        self.assertIn('brokerMaxLot >= brokerMinLot', body)
        normalize = body.index('CTradeMgrPricing::NormalizeVolume(symbol, lotSize)')
        risk = body.index('CalculateTradeRisk(symbol, candidate.lotSize')
        request = body.index('tradeReq.lotSize = candidate.lotSize')
        final_gate = body.index('ValidateTradeRequest(tradeReq, ' + chr(34) + 'final-lot' + chr(34))
        self.assertLess(normalize, risk)
        self.assertLess(risk, request)
        self.assertLess(request, final_gate)
        self.assertIn('if(normalizedLot < lotSize)', body)
        self.assertIn('lotSize = normalizedLot;', body)
        self.assertIn('normalizedLot > lotSize', body)

    def test_grid_close_failure_retains_ownership_and_blocks_new_levels(self):
        close_all = function_body(self.grid_engine, "bool CloseAllGrids(")
        manage = function_body(self.grid_engine, "void ManageGridPositions(")
        failed_close = close_all.index("if(!m_execution.ClosePositionTicket(")
        failed_close_continue = close_all.index("continue;", failed_close)
        state_clear = close_all.index("m_symbolStates[idx].levels[l].isActive = false;", failed_close)
        aggregate_clear = close_all.index("m_symbolStates[idx].activeLevelCount = 0;")

        self.assertLess(failed_close_continue, state_clear)
        self.assertLess(close_all.index("if(allClosed)", failed_close), aggregate_clear)
        self.assertIn("ownership and risk state retained", close_all)
        self.assertIn("blocking additional entries until the position ticket resolves", manage)
        self.assertNotIn("GetLastTicket()", self.grid_execution)


if __name__ == "__main__":
    unittest.main()
