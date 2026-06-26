import { BrowserRouter, Routes, Route } from 'react-router-dom';
import Sidebar from './components/layout/Sidebar';
import Header from './components/layout/Header';
import OverviewPage from './pages/OverviewPage';
import ChartsPage from './pages/ChartsPage';
import PositionsPage from './pages/PositionsPage';
import StrategiesPage from './pages/StrategiesPage';
import RiskPage from './pages/RiskPage';
import AIPage from './pages/AIPage';
import LogsPage from './pages/LogsPage';
import ControlPage from './pages/ControlPage';
import { useEAState } from './hooks/useEAState';

function AppContent() {
  const { isConnected, state } = useEAState();
  const executionMode = state?.execution_mode ?? 'UNKNOWN';

  return (
    <div className="flex h-screen overflow-hidden bg-bg">
      <Sidebar />
      <div className="flex flex-col flex-1 min-w-0">
        <Header isConnected={isConnected} executionMode={executionMode} />
        <main className="flex-1 overflow-auto bg-bg">
          <Routes>
            <Route path="/" element={<OverviewPage />} />
            <Route path="/charts" element={<ChartsPage />} />
            <Route path="/positions" element={<PositionsPage />} />
            <Route path="/strategies" element={<StrategiesPage />} />
            <Route path="/risk" element={<RiskPage />} />
            <Route path="/ai" element={<AIPage />} />
            <Route path="/logs" element={<LogsPage />} />
            <Route path="/control" element={<ControlPage />} />
          </Routes>
        </main>
      </div>
    </div>
  );
}

export default function App() {
  return (
    <BrowserRouter>
      <AppContent />
    </BrowserRouter>
  );
}
