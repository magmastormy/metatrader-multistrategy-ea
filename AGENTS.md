# AGENTS Operational Manual

*Single source of truth for every AI agent collaborating on [metatrader-multistrategy-ea](cci:7://file:///d:/TraeProjects/metatrader-multistrategy-ea:0:0-0:0).*

---

## 1. Project Purpose
- Deliver a production-grade, multi-strategy Expert Advisor (EA) for MetaTrader 5 that orchestrates diverse trading strategies with adaptive risk, comprehensive monitoring, and automated execution.
- Integrate a Python AI subsystem ([python-ai/](cci:7://file:///d:/TraeProjects/metatrader-multistrategy-ea/python-ai:0:0-0:0)) to produce predictive signals, manage ML models, and bridge analytics into the MQL5 trading core using ZeroMQ, TCP, or file-based channels.
- Maintain enterprise-ready automation, documentation, and tooling so the trading stack remains auditable, extensible, and resilient.

---

## 2. Coding Conventions and Style Rules
### 2.1 General
- Preserve existing naming patterns; do not introduce new casing styles without justification.
- Use four-space indentation, avoid tabs, and keep lines ≤120 characters unless readability would suffer.
- Prefer descriptive identifiers; add concise comments only when intent is non-obvious.
- Keep commits atomic and narrowly scoped.

### 2.2 MQL5 (`.mqh` / `.mq5`)
- Classes/structs: PascalCase (`StrategyFactory`). Functions/methods: PascalCase or UpperCamelCase, matching local precedent.
- Constants/macros: ALL_CAPS with underscores.
- Keep interface headers organized under [Core/](cci:7://file:///d:/TraeProjects/metatrader-multistrategy-ea/Core:0:0-0:0), [Strategies/](cci:7://file:///d:/TraeProjects/metatrader-multistrategy-ea/Strategies:0:0-0:0), [Interfaces/](cci:7://file:///d:/TraeProjects/metatrader-multistrategy-ea/Interfaces:0:0-0:0), etc. Maintain include guards.
- Use utilities from `Core/Utils/ErrorHandling.mqh` instead of ad-hoc alerts.
- Respect existing module boundaries—place shared types in `Core/Utils/`, strategy logic in [Strategies/](cci:7://file:///d:/TraeProjects/metatrader-multistrategy-ea/Strategies:0:0-0:0), etc.

### 2.3 Python ([python-ai/](cci:7://file:///d:/TraeProjects/metatrader-multistrategy-ea/python-ai:0:0-0:0))
- Follow PEP 8. Before submitting changes, run `black`, `isort`, and `ruff` (wrappers available under `.trunk/tools/`).
- Type-hint public functions and prefer dependency injection over globals.
- Use the standard `logging` module; never print for diagnostics.
- All configuration I/O must flow through helpers in `python-ai/config`; avoid hardcoding ports, paths, or secrets.

### 2.4 PowerShell / Batch
- Ensure idempotency and parameterize reusable logic.
- Provide comment-based help for new PowerShell functions.
- Scripts must run from repository root without needing `cd`.

### 2.5 Documentation & Markdown
- Use ATX headings, bullet lists, and tables consistently; keep one sentence per line for cleaner diffs.
- Update relevant docs in [Documentation/](cci:7://file:///d:/TraeProjects/metatrader-multistrategy-ea/Documentation:0:0-0:0) whenever behavior, dependencies, or workflows change.

---

## 3. Build Instructions
- **MetaTrader EA:** Run the unified PowerShell workflow:
  ```powershell
  powershell -ExecutionPolicy Bypass -File sync_and_compile.ps1
  ```
  Optional parameters:
  - `-MetaTraderRoot "<path>"` to point at a non-default MT5 installation.
  - `-ProjectRoot "<path>"` when invoking from outside the repo.
  - `-SkipSync` to compile without mirroring files.
  The script mirrors sources into MT5, compiles the main EA and AI trainer, and streams logs from `compile_full.log` and `compile_trainer.log`.
  Automated pipelines may also leverage [deploy_and_compile.ps1](cci:7://file:///d:/TraeProjects/metatrader-multistrategy-ea/deploy_and_compile.ps1:0:0-0:0) or targeted fix scripts (e.g., [fix_all_core_files.ps1](cci:7://file:///d:/TraeProjects/metatrader-multistrategy-ea/fix_all_core_files.ps1:0:0-0:0)).
- **Python AI subsystem:**  
  ```bash
  cd python-ai
  python -m venv .venv
  .venv\Scripts\activate
  pip install -r requirements.txt
  ```
  Alternatively, execute `INSTALL_WITH_CONDA.bat` for Conda environments.
- **Bridges:** Use `python-ai/start_ai_system.bat` to launch ZeroMQ/TCP/file bridges with automatic fallback.
- **Batch automation:** Review scripts such as [run_all_fixes.bat](cci:7://file:///d:/TraeProjects/metatrader-multistrategy-ea/run_all_fixes.bat:0:0-0:0) before execution to understand scope and side effects.

---

## 4. Test Instructions
- `python-ai/test_harness.py`: Bridge/pipeline validation.
- `python-ai/test_system.py` (mirrored in [Documentation/test_system.py](cci:7://file:///d:/TraeProjects/metatrader-multistrategy-ea/Documentation/test_system.py:0:0-0:0)): End-to-end AI system checks.
- After modifying MQL modules, recompile and review [compile_result.log](cci:7://file:///d:/TraeProjects/metatrader-multistrategy-ea/compile_result.log:0:0-0:0); perform MT5 Strategy Tester runs for substantive logic changes.
- Retraining workflows in `python-ai/retraining/` must conclude with `python-ai/utils/validation.py`.
- Log significant results or regressions in [Documentation/TEST_RESULTS.md](cci:7://file:///d:/TraeProjects/metatrader-multistrategy-ea/Documentation/TEST_RESULTS.md:0:0-0:0).

---

## 5. Dependency Management Rules
- Python dependencies live **only** in `python-ai/requirements.txt`; keep Conda scripts synchronized. Do not install global packages.
- MQL dependencies must be vendored headers within this repo. External includes require attribution and documentation.
- Bridge configuration in `python-ai/config/*.yaml` must match MQL constants; revise docs and this manual when endpoints or ports change.
- [.trunk/](cci:7://file:///d:/TraeProjects/metatrader-multistrategy-ea/.trunk:0:0-0:0) tooling defines lint/format enforcement—coordinate before altering plugins or versions.

---

## 6. File Creation, Modification, and Deletion Policy
- **Strict rule:** Do **not** recreate or overwrite existing files. Modify them in place; never delete/recreate to apply edits.
- Always consult Section 7 (folder tree) before generating content to confirm whether a target path already exists.
- Place new files only in folders explicitly designated for that content (see Section 8).
- Deletions require validation against [Documentation/OBSOLETE_FILES.md](cci:7://file:///d:/TraeProjects/metatrader-multistrategy-ea/Documentation/OBSOLETE_FILES.md:0:0-0:0) and, if executed, must be recorded in [Documentation/FILE_REORGANIZATION_MAP.md](cci:7://file:///d:/TraeProjects/metatrader-multistrategy-ea/Documentation/FILE_REORGANIZATION_MAP.md:0:0-0:0).
- When adding modules, accompany them with tests, docs, and configuration updates as needed.
- Keep edits atomic—avoid mixing unrelated changes.

---

## 7. Repository Structure Reference
*Generated via `tree /F /A` from the repository root. Always review this tree before editing or creating files.*

```text
Folder PATH listing
Volume serial number is DA30-A597
D:.
|   AGENTS.md
|   AGENTS_tree.txt
|   DirectTradeExecution.mqh
|   DynamicExitManager.mqh
|   IndicatorManager.mqh
|   IntelligentRiskFunctions.mqh
|   MultiStrategyAutonomousEA.mq5
|   MultiStrategySelection.mqh
|   PreTradeValidator.mqh
|   ProcessIntelligentTrading.mqh
|   RiskManager.mqh
|   sync_and_compile.ps1
|   TestSocket.mq5
|   WalkForwardOptimizer.mqh
|
+---.trunk
+---AIModules
|       EnsembleMetaLearner.mqh
|       MarketRegimeDetector.mqh
|       NextGenBrainTrainer.ex5
|       NextGenBrainTrainer.mq5
|       NextGenStrategyBrain.mqh
|       PythonBridge.mqh
|       TransformerBrain.mqh
|       UncertaintyQuantifier.mqh
|
+---Config
|       StrategyConfig.mqh
|
+---Core
|   |   CBaseStrategy.mqh
|   |   MultiSymbolRiskAllocator.mqh
|   |   MultiTimeframeAnalyzer.mqh
|   |
|   +---AI
|   |       AIPerformanceFeedback.mqh
|   |       AIStrategyOrchestrator.mqh
|   |       EnhancedEnsembleVotingSystem.mqh
|   |
|   +---Connectivity
|   |       BrokerConnectionManager.mqh
|   |       DerivManager.mqh
|   |       HTTPClient.mqh
|   |       IntegrationHub.mqh
|   |
|   +---Engines
|   |       AIEngine.mqh
|   |       ConfluenceEngine.mqh
|   |       LiquidityEngine.mqh
|   |       MarketAnalysis.mqh
|   |       StructureEngine.mqh
|   |       TradingEngine.mqh
|   |       TrendEngine.mqh
|   |       VolatilityEngine.mqh
|   |
|   +---Management
|   |       EnterpriseStrategyManager.mqh
|   |
|   +---Market
|   |       CrashBoomSpikeDetector.mqh
|   |       MarketRegimeDetector.mqh
|   |       StepIndexLevelBreaker.mqh
|   |       SymbolDiversificationOptimizer.mqh
|   |       SyntheticIndexHealthMonitor.mqh
|   |       VolatilityIndexOptimizer.mqh
|   |
|   +---Monitoring
|   |       PerformanceAnalytics.mqh
|   |       SystemHealthMonitor.mqh
|   |
|   +---Pipeline
|   |       UnifiedSignalPipeline.mqh
|   |
|   +---Risk
|   |       AdaptiveRiskManager.mqh
|   |       EnhancedRiskManager.mqh
|   |       PortfolioRiskManager.mqh
|   |       PositionSizer.mqh
|   |       RiskValidationGate.mqh
|   |       SafetyLayer.mqh
|   |
|   +---Signals
|   |       HedgingProtection.mqh
|   |       SignalDiagnostics.mqh
|   |       TimeframeConsistency.mqh
|   |
|   +---Strategy
|   |       MarketConditionStrategySelector.mqh
|   |       PerformanceBasedStrategyAdapter.mqh
|   |       StrategyBase.mqh
|   |       StrategyFactory.mqh
|   |       StrategyFunctions.mqh
|   |       StrategyManager.mqh
|   |       StrategyWrapper.mqh
|   |
|   +---Trading
|   |       DealInfo.mqh
|   |       HistoryOrderInfo.mqh
|   |       OrderInfo.mqh
|   |       PositionInfo.mqh
|   |       ProgressiveTakeProfit.mqh
|   |       TPManagerEntry.mqh
|   |       Trade.mqh
|   |       TradeManager.mqh
|   |
|   +---Utils
|   |       CommonTypes.mqh
|   |       DataTypes.mqh
|   |       Enums.mqh
|   |       ErrorHandling.mqh
|   |       File.mqh
|   |       FileTxt.mqh
|   |       Instruments.mqh
|   |       ModeManager.mqh
|   |       ResourceManager.mqh
|   |       SessionManager.mqh
|   |       SymbolContext.mqh
|   |
|   \---Visualization
|           ChartDrawingManager.mqh
|           OrderBlockVisualizer.mqh
|           SMCStructureVisualizer.mqh
|
+---Documentation
|       ARCHITECTURE.md
|       CONDA_QUICKSTART.md
|       ENTERPRISE_UPGRADE_COMPLETE.md
|       FILE_REORGANIZATION_MAP.md
|       FIX_SUMMARY_SILENCE_RESTORED.md
|       INSTALLATION.md
|       INTEGRATION_UPDATE_SUMMARY.md
|       MIGRATION_GUIDE.md
|       OBSOLETE_FILES.md
|       PROJECT_SUMMARY.md
|       PYTHON_AI_INTEGRATION.md
|       QUICKSTART.md
|       RETRAINING_GUIDE.md
|       RETRAINING_SUMMARY.md
|       SIGNAL_REPAIR_REPORT.md
|       STRATEGY_REFINEMENT_REPORT.md
|       TEST_RESULTS.md
|       test_system.py
|
+---Include
|   \---Indicators
|           Oscillators.mqh
|           RSI.mqh
|
+---Interfaces
|       CBaseStrategy.mqh
|       IStrategy.mqh
|
+---python-ai
|   |   activate_ai_nexus.bat
|   |   INSTALL_WITH_CONDA.bat
|   |   main.py
|   |   MQL5_INTEGRATION.md
|   |   QUICKSTART.md
|   |   README.md
|   |   requirements.txt
|   |   run_retraining.bat
|   |   setup_ai_nexus.bat
|   |   start_ai_system.bat
|   |   start_scheduler.bat
|   |   test_harness.py
|   |
|   +---bridge
|   |   |   file_pipe.py
|   |   |   message_protocol.py
|   |   |   socket_server.py
|   |   |   zmq_server.py
|   |   |   __init__.py
|   |   |
|   |   \---__pycache__
|   |           file_pipe.cpython-314.pyc
|   |           message_protocol.cpython-314.pyc
|   |           socket_server.cpython-314.pyc
|   |           zmq_server.cpython-314.pyc
|   |           __init__.cpython-314.pyc
|   |
|   +---config
|   |       bridge.yaml
|   |       features.yaml
|   |       model_config.yaml
|   |
|   +---core
|   |   |   analytics.py
|   |   |   data_loader.py
|   |   |   feature_engineer.py
|   |   |   model_manager.py
|   |   |   risk_engine.py
|   |   |   signal_generator.py
|   |   |   __init__.py
|   |   |
|   |   \---__pycache__
|   |           analytics.cpython-314.pyc
|   |           data_loader.cpython-314.pyc
|   |           feature_engineer.cpython-314.pyc
|   |           model_manager.cpython-314.pyc
|   |           risk_engine.cpython-314.pyc
|   |           signal_generator.cpython-314.pyc
|   |           __init__.cpython-314.pyc
|   |
|   +---logs
|   |       ai_runtime.log
|   |
|   +---models
|   |   |   trading_model.onnx
|   |   |   transformer_model.onnx
|   |   |
|   |   \---training_scripts
|   |           train_lgbm.py
|   |           train_transformer.py
|   |           __init__.py
|   |
|   +---retraining
|   |       auto_scheduler.py
|   |       data_ingestion.py
|   |       feature_engineering.py
|   |       model_evaluation.py
|   |       model_registry.py
|   |       model_training.py
|   |       retrain_loop.py
|   |       __init__.py
|   |
|   +---utils
|   |   |   data_utils.py
|   |   |   math_utils.py
|   |   |   time_utils.py
|   |   |   validation.py
|   |   |   __init__.py
|   |   |
|   |   \---__pycache__
|   |           math_utils.cpython-314.pyc
|   |           time_utils.cpython-314.pyc
|   |           __init__.cpython-314.pyc
|   |
|   \---__pycache__
|           test_system.cpython-314.pyc
|
+---Scripts
|       cleanup_old_files.bat
|       live_mt5_to_ai_automation.py
|
+---Strategies
|       Core.mqh
|       RSI.mqh
|       SimpleMomentumStrategy.mqh
|       StrategyBollinger.mqh
|       StrategyBollingerBreakout.mqh
|       StrategyBreakout.mqh
|       StrategyCorrelationMatrix.mqh
|       StrategyElliott.mqh
|       StrategyElliottWave.mqh
|       StrategyElliottWaveEnhanced.mqh
|       StrategyFactory.mqh
|       StrategyFairValueGap.mqh
|       StrategyFibonacci.mqh
|       StrategyHarmonicPatterns.mqh
|       StrategyIchimoku.mqh
|       StrategyMACD.mqh
|       StrategyMeanReversion.mqh
|       StrategyOrderBlock.mqh
|       StrategyOrderBlockFVG.mqh
|       StrategyRSI.mqh
|       StrategySMC.mqh
|       StrategyStepIndex.mqh
|       StrategySupplyDemand.mqh
|       StrategySwing.mqh
|       StrategyTrend.mqh
|       StrategyVolatility.mqh
|
+---userReports
|       ea_logs.log
|       userWritten_modeltrainingloop.md
|       userWritten_ProjectUpgrade.md
|
\---Utilities
        File.mqh
        FileTxt.mqh
        Utilities.mqh
```

---

## 8. Folder-by-Folder Agent Guidelines
*Consult this section before acting within any directory.*

- **Root (`D:.`)**
  - Houses orchestration scripts, global logs, compiled binaries, and primary EA sources.
  - **Behavior:** Only modify files listed in Section 7; do not add new top-level scripts without project owner approval. New tooling belongs under `.trunk/tools/` or [Scripts/](cci:7://file:///d:/TraeProjects/metatrader-multistrategy-ea/Scripts:0:0-0:0).

- **[.trunk/](cci:7://file:///d:/TraeProjects/metatrader-multistrategy-ea/.trunk:0:0-0:0)**
  - Trunk-based automation configs, cached outputs, and lint wrappers.
  - **Behavior:** Adjust only when updating lint/build tooling. For new lint integrations, extend `trunk.yaml` and matching files under `.trunk/tools/`.

- **[AIModules/](cci:7://file:///d:/TraeProjects/metatrader-multistrategy-ea/AIModules:0:0-0:0)**
  - MQL5 AI integration headers and trainers.
  - **Behavior:** Add new AI modules here only after coordinating with `Core/AI`. Maintain one class per file.

- **[Config/](cci:7://file:///d:/TraeProjects/metatrader-multistrategy-ea/Config:0:0-0:0)**
  - MQL configuration headers (e.g., `StrategyConfig.mqh`).
  - **Behavior:** Place new shared config headers here. Avoid duplicating config constants; cross-reference `python-ai/config`.

- **[Core/](cci:7://file:///d:/TraeProjects/metatrader-multistrategy-ea/Core:0:0-0:0) (and subfolders)**
  - Central EA infrastructure segmented by concern (AI, Connectivity, Engines, Management, Market, Monitoring, Pipeline, Risk, Signals, Strategy, Trading, Utils, Visualization).
  - **Behavior:** Keep each module cohesive. Before adding files, verify corresponding functionality isn’t already implemented. New utilities go to `Core/Utils/` with consistent naming.

- **[Documentation/](cci:7://file:///d:/TraeProjects/metatrader-multistrategy-ea/Documentation:0:0-0:0)**
  - Comprehensive project documentation.
  - **Behavior:** Update relevant documents when behavior changes. New guides go here with descriptive names. Do not duplicate existing topics.

- **`Include/Indicators/`**
  - Indicator-specific headers.
  - **Behavior:** Place new indicators here, using existing naming conventions.

- **[Interfaces/](cci:7://file:///d:/TraeProjects/metatrader-multistrategy-ea/Interfaces:0:0-0:0)**
  - Shared interface definitions (`CBaseStrategy.mqh`, `IStrategy.mqh`).
  - **Behavior:** Extend interfaces cautiously; ensure downstream implementers are updated.

- **[python-ai/](cci:7://file:///d:/TraeProjects/metatrader-multistrategy-ea/python-ai:0:0-0:0) and subdirectories**
  - Python AI subsystem: orchestration (`core/`), bridges, configs, models, retraining, utils.
  - **Behavior:** Follow Python guidelines from Section 2.3. Place new models in `models/` or `models/training_scripts`, new configs in `config/`, new utilities under `utils/`. Keep `__init__.py` files updated.

- **[Scripts/](cci:7://file:///d:/TraeProjects/metatrader-multistrategy-ea/Scripts:0:0-0:0)**
  - Automation scripts bridging MT5 and AI.
  - **Behavior:** New automation scripts belong here with descriptive names and documentation.

- **[Strategies/](cci:7://file:///d:/TraeProjects/metatrader-multistrategy-ea/Strategies:0:0-0:0)**
  - Individual trading strategy modules.
  - **Behavior:** Add new strategies with `Strategy<Descriptor>.mqh` naming; update factory/manager modules accordingly.

- **[userReports/](cci:7://file:///d:/TraeProjects/metatrader-multistrategy-ea/userReports:0:0-0:0)**
  - User-authored documentation and logs.
  - **Behavior:** Store additional reports or logs here; avoid modifying user-authored historical documents unless requested.

- **[Utilities/](cci:7://file:///d:/TraeProjects/metatrader-multistrategy-ea/Utilities:0:0-0:0)**
  - Legacy utility headers.
  - **Behavior:** Only add utility headers if they must remain separate from `Core/Utils/`; otherwise prefer the newer structure.

- **Binary/Cache folders (e.g., `python-ai/__pycache__/`, `.trunk/out/`)**
  - Generated artifacts.
  - **Behavior:** Do not edit. Never check in additional cache files.

---

## 9. Architectural Decisions & Constraints
- **Modular EA core:** Each domain (signals, risk, engines, trading) resides in targeted folders to minimize coupling. New features must honor this separation.
- **Python bridge-first architecture:** ZeroMQ is primary; TCP/file-based bridges are fallbacks. Any bridge change must maintain backward compatibility and update both sides.
- **Configuration via YAML & header constants:** Keep Python and MQL configurations synchronized; centralize definitions rather than duplicating.
- **Comprehensive logging:** Both MQL and Python sides must log through existing utilities to maintain audit trails.
- **Automation bias:** Numerous fix/compile scripts exist; prefer extending existing automation over introducing bespoke runbooks.

---

## 10. Safe Extension Guidelines
1. **Plan scope:** Identify target modules via Section 7; avoid touching unrelated areas.
2. **Review dependencies:** Confirm no existing component already solves the problem.
3. **Implement incrementally:** Update code, tests, configs, and documentation together.
4. **Validate:** Run relevant tests (Section 4) and linters before finalizing changes.
5. **Document:** Record architectural or dependency changes in [Documentation/](cci:7://file:///d:/TraeProjects/metatrader-multistrategy-ea/Documentation:0:0-0:0) and update this AGENTS.md if the folder structure changes.

---

## 11. Operational Checklist for Agents
- [ ] Review Section 7 to confirm target file locations.
- [ ] Respect Section 6—never recreate existing files.
- [ ] Follow coding conventions from Section 2.
- [ ] Apply build/test routines in Sections 3–4 after changes.
- [ ] Update documentation when behavior or interfaces change.
- [ ] When in doubt, consult architectural guidance (Section 9) and extension practices (Section 10).

---

*End of AGENTS.md — Always reference this manual before modifying the repository.*