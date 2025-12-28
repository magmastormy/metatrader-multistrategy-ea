# Project Context Notes
 
 - EA operates across multiple strategies; recent focus on order block improvements, confidence filtering, and indicator warmups.
 - MarketAnalysis engine now enforces symbol availability checks and extended warmup (60s) with retry silence (5 min).
 - StrategyBase enforces minimum signal confidence of 0.30 and tracks low-confidence filters.
 - StrategyOrderBlock throttles scans to 60 seconds and deduplicates logging; continues checking blocks while skipping low-confidence touches.
 - New-bar updates are dispatched via `CEnterpriseStrategyManager::OnNewBar(symbol,timeframe)` which calls `IStrategy::OnNewBar(symbol,timeframe)` polymorphically; strategies should refresh/prime indicator data there (e.g., Swing now uses persistent MA/RSI handles).
