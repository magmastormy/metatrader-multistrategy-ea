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
        <div className="col-span-6 bg-surface border border-border p-6">
          <h3 className="text-text-muted text-xs uppercase tracking-wider font-medium mb-4">Execution Mode</h3>
          <p className="text-2xl font-bold text-text mb-4">{executionMode}</p>
          <div className="flex gap-3">
            <button
              onClick={() => { sendCommand('set_mode', { mode: 'SHADOW' }); handleFeedback('Switching to SHADOW mode'); }}
              className={`px-4 py-2 text-sm font-semibold transition-all duration-200 ${
                executionMode === 'SHADOW'
                  ? 'bg-[#c8f53a]/20 text-[#c8f53a] border border-[#c8f53a]/40'
                  : 'bg-[#0e0e0e] text-text-muted border border-border hover:border-[#c8f53a]/30 hover:text-[#c8f53a]'
              }`}
            >
              SHADOW
            </button>
            <button
              onClick={() => { sendCommand('set_mode', { mode: 'LIVE' }); handleFeedback('Switching to LIVE mode'); }}
              className={`px-4 py-2 text-sm font-semibold transition-all duration-200 ${
                executionMode === 'LIVE'
                  ? 'bg-[#e8541a]/20 text-[#e8541a] border border-[#e8541a]/40'
                  : 'bg-[#0e0e0e] text-text-muted border border-border hover:border-[#e8541a]/30 hover:text-[#e8541a]'
              }`}
            >
              LIVE
            </button>
            <button
              onClick={() => { sendCommand('set_mode', { mode: 'OFF' }); handleFeedback('Switching to OFF mode'); }}
              className={`px-4 py-2 text-sm font-semibold transition-all duration-200 ${
                executionMode === 'OFF'
                  ? 'bg-[#2a2a2a]/50 text-text-muted border border-border'
                  : 'bg-[#0e0e0e] text-text-muted border border-border hover:border-[#8a8a8a] hover:text-text'
              }`}
            >
              OFF
            </button>
          </div>
        </div>

        {/* Emergency stop */}
        <div className="col-span-6 bg-surface border border-border p-6">
          <h3 className="text-text-muted text-xs uppercase tracking-wider font-medium mb-4">Emergency Stop</h3>
          <p className="text-text-muted text-sm mb-4">
            Immediately halt all trading activity and close open positions.
          </p>
          {!confirmEmergency ? (
            <button
              onClick={() => setConfirmEmergency(true)}
              className="px-6 py-3 bg-[#e8541a]/15 text-[#e8541a] font-bold text-sm border border-[#e8541a]/30 hover:bg-[#e8541a]/25 transition-all duration-200"
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
                className="px-6 py-3 bg-[#e8541a] text-[#080808] font-bold text-sm hover:bg-[#e8541a]/90 transition-all duration-200 animate-pulse-solid"
              >
                CONFIRM STOP
              </button>
              <button
                onClick={() => setConfirmEmergency(false)}
                className="px-4 py-3 bg-[#0e0e0e] text-text-muted text-sm border border-border hover:border-[#2a2a2a] transition-all duration-200"
              >
                CANCEL
              </button>
            </div>
          )}
        </div>

        {/* Parameter editor */}
        <div className="col-span-6 bg-surface border border-border p-6">
          <h3 className="text-text-muted text-xs uppercase tracking-wider font-medium mb-4">Parameter Editor</h3>
          <div className="flex gap-3">
            <input
              type="text"
              placeholder="PARAMETER NAME"
              value={paramName}
              onChange={(e) => setParamName(e.target.value)}
              className="flex-1 bg-[#0e0e0e] text-text text-sm px-3 py-2 border border-border focus:border-[#c8f53a] focus:outline-none placeholder:text-text-muted transition-colors duration-200"
            />
            <input
              type="text"
              placeholder="VALUE"
              value={paramValue}
              onChange={(e) => setParamValue(e.target.value)}
              className="flex-1 bg-[#0e0e0e] text-text text-sm px-3 py-2 border border-border focus:border-[#c8f53a] focus:outline-none placeholder:text-text-muted transition-colors duration-200"
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
              className="px-4 py-2 bg-[#c8f53a]/15 text-[#c8f53a] text-sm font-semibold border border-[#c8f53a]/30 hover:bg-[#c8f53a]/25 transition-all duration-200"
            >
              APPLY
            </button>
          </div>
        </div>

        {/* Feedback */}
        <div className="col-span-6 bg-surface border border-border p-6">
          <h3 className="text-text-muted text-xs uppercase tracking-wider font-medium mb-4">Status</h3>
          {feedback ? (
            <p className="text-[#c8f53a] text-sm font-medium animate-fade-in">{feedback}</p>
          ) : (
            <p className="text-text-muted text-sm">READY</p>
          )}
        </div>
      </div>
    </PageContainer>
  );
}
