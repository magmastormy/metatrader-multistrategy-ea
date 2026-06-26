import PageContainer from '../components/layout/PageContainer';

export default function ChartsPage() {
  return (
    <PageContainer title="Charts">
      <div className="bg-surface border border-border p-8 flex flex-col items-center justify-center h-[60vh]">
        <div className="text-[#c8f53a]/40 mb-4">
          <svg width="64" height="64" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
            <path d="M3 3v18h18" />
            <path d="M7 16l4-8 4 4 4-6" />
          </svg>
        </div>
        <h3 className="text-text text-lg font-semibold mb-2">TRADINGVIEW LIGHTWEIGHT CHARTS</h3>
        <p className="text-text-muted text-sm text-center max-w-md">
          Interactive candlestick charts powered by lightweight-charts will be rendered here.
          Connect to a live EA session to see real-time price data.
        </p>
      </div>
    </PageContainer>
  );
}
