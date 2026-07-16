import { BrowserRouter, Routes, Route } from 'react-router-dom';
import Sidebar from './components/layout/Sidebar';
import Header from './components/layout/Header';
import { useEAState } from './hooks/useEAState';

function AppContent() {
  const { isConnected, state } = useEAState();
  const executionMode = state?.execution_mode ?? 'UNKNOWN';

  return (
    <div className="flex h-screen overflow-hidden bg-bg-primary">
      <Sidebar />
      <div className="flex flex-col flex-1 min-w-0 ml-16">
        <Header isConnected={isConnected} executionMode={executionMode} />
        <main className="flex-1 overflow-auto bg-bg-primary">
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

function OverviewPage() { return <div className="p-6">Overview Page - Coming Soon</div>; }
function ChartsPage() { return <div className="p-6">Charts Page - Coming Soon</div>; }
function PositionsPage() { return <div className="p-6">Positions Page - Coming Soon</div>; }
function StrategiesPage() { return <div className="p-6">Strategies Page - Coming Soon</div>; }
function RiskPage() { return <div className="p-6">Risk Page - Coming Soon</div>; }
function AIPage() { return <div className="p-6">AI Page - Coming Soon</div>; }
function LogsPage() { return <div className="p-6">Logs Page - Coming Soon</div>; }
function ControlPage() { return <div className="p-6">Control Page - Coming Soon</div>; }

export default function App() {
  return (
    <BrowserRouter>
      <AppContent />
    </BrowserRouter>
  );
}