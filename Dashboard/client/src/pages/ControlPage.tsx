import { useState } from 'react';
import { useEAState } from '../hooks/useEAState';
import PageContainer from '../components/layout/PageContainer';

export default function ControlPage() {
  const { state, isConnected, sendCommand } = useEAState();
  const [paramName, setParamName] = useState('');
  const [paramValue, setParamValue] = useState('');
  const [confirmEmergency, setConfirmEmergency] = useState(false);
  const [feedback, setFeedback] = useState('');

  const executionMode = state?.execution_mode ?? 'UNKNOWN';

  const handleFeedback = (msg: string) => {
    setFeedback(msg);
    setTimeout(() => setFeedback(''), 3000);
  };

  if (!isConnected) {
    return (
      <PageContainer title="Control">
        <p className="text-text-muted">Connecting...</p>
      </PageContainer>
    );
  }

  return (
    <PageContainer title="Control">
      <div className="grid grid-cols-12 gap-6">
        {/* Execution mode */}
        <div className="col-span-6 glass-card p-6">
          <h3 className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-4">Execution Mode</h3>
          <p className="text-2xl font-bold text-text-primary mb-4">{executionMode}</p>
          <div className="flex gap-3">
            <button
              onClick={() => { sendCommand('set_mode', { mode: 'SHADOW' }); handleFeedback('Switching to SHADOW mode'); }}
              className={`px-4 py-2 rounded-lg text-sm font-semibold transition-all duration-200 ${
                executionMode === 'SHADOW'
                  ? 'bg-accent-amber/20 text-accent-amber border border-accent-amber/40'
                  : 'bg-surface-700 text-text-secondary border border-surface-600 hover:border-accent-amber/30 hover:text-accent-amber'
              }`}
            >
              Shadow
            </button>
            <button
              onClick={() => { sendCommand('set_mode', { mode: 'LIVE' }); handleFeedback('Switching to LIVE mode'); }}
              className={`px-4 py-2 rounded-lg text-sm font-semibold transition-all duration-200 ${
                executionMode === 'LIVE'
                  ? 'bg-accent-green/20 text-accent-green border border-accent-green/40'
                  : 'bg-surface-700 text-text-secondary border border-surface-600 hover:border-accent-green/30 hover:text-accent-green'
              }`}
            >
              Live
            </button>
            <button
              onClick={() => { sendCommand('set_mode', { mode: 'OFF' }); handleFeedback('Switching to OFF mode'); }}
              className={`px-4 py-2 rounded-lg text-sm font-semibold transition-all duration-200 ${
                executionMode === 'OFF'
                  ? 'bg-surface-600/50 text-text-muted border border-surface-500'
                  : 'bg-surface-700 text-text-secondary border border-surface-600 hover:border-surface-500 hover:text-text-muted'
              }`}
            >
              Off
            </button>
          </div>
        </div>

        {/* Emergency stop */}
        <div className="col-span-6 glass-card p-6">
          <h3 className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-4">Emergency Stop</h3>
          <p className="text-text-muted text-sm mb-4">
            Immediately halt all trading activity and close open positions.
          </p>
          {!confirmEmergency ? (
            <button
              onClick={() => setConfirmEmergency(true)}
              className="px-6 py-3 rounded-lg bg-accent-red/15 text-accent-red font-bold text-sm border border-accent-red/30 hover:bg-accent-red/25 hover:scale-[1.03] transition-all duration-200"
            >
              EMERGENCY STOP
            </button>
          ) : (
            <div className="flex items-center gap-3">
              <button
                onClick={() => {
                  sendCommand('emergency_stop');
                  setConfirmEmergency(false);
                  handleFeedback('Emergency stop activated!');
                }}
                className="px-6 py-3 rounded-lg bg-accent-red text-white font-bold text-sm hover:bg-accent-red/90 hover:scale-[1.03] transition-all duration-200 animate-pulse"
              >
                CONFIRM STOP
              </button>
              <button
                onClick={() => setConfirmEmergency(false)}
                className="px-4 py-3 rounded-lg bg-surface-700 text-text-secondary text-sm border border-surface-600 hover:border-surface-500 transition-all duration-200"
              >
                Cancel
              </button>
            </div>
          )}
        </div>

        {/* Parameter editor */}
        <div className="col-span-6 glass-card p-6">
          <h3 className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-4">Parameter Editor</h3>
          <div className="flex gap-3">
            <input
              type="text"
              placeholder="Parameter name"
              value={paramName}
              onChange={(e) => setParamName(e.target.value)}
              className="flex-1 bg-surface-700 text-text-primary text-sm rounded-lg px-3 py-2 border border-surface-600 focus:border-accent-cyan focus:outline-none placeholder:text-text-muted transition-colors duration-200"
            />
            <input
              type="text"
              placeholder="Value"
              value={paramValue}
              onChange={(e) => setParamValue(e.target.value)}
              className="flex-1 bg-surface-700 text-text-primary text-sm rounded-lg px-3 py-2 border border-surface-600 focus:border-accent-cyan focus:outline-none placeholder:text-text-muted transition-colors duration-200"
            />
            <button
              onClick={() => {
                if (paramName && paramValue) {
                  sendCommand('set_param', { name: paramName, value: paramValue });
                  handleFeedback(`Set ${paramName} = ${paramValue}`);
                  setParamName('');
                  setParamValue('');
                }
              }}
              className="px-4 py-2 rounded-lg bg-accent-cyan/15 text-accent-cyan text-sm font-semibold border border-accent-cyan/30 hover:bg-accent-cyan/25 hover:scale-[1.03] transition-all duration-200"
            >
              Apply
            </button>
          </div>
        </div>

        {/* Feedback */}
        <div className="col-span-6 glass-card p-6">
          <h3 className="text-text-secondary text-xs uppercase tracking-wider font-medium mb-4">Status</h3>
          {feedback ? (
            <p className="text-accent-cyan text-sm font-medium animate-fade-in">{feedback}</p>
          ) : (
            <p className="text-text-muted text-sm">Ready</p>
          )}
        </div>
      </div>
    </PageContainer>
  );
}
