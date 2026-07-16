import type { ReactNode } from 'react';

interface PageContainerProps {
  title: string;
  subtitle?: string;
  action?: ReactNode;
  children: ReactNode;
  className?: string;
}

export default function PageContainer({ title, subtitle, action, children, className = '' }: PageContainerProps) {
  return (
    <div className={`page-container ${className}`}>
      <div className="page-header">
        <div className="page-header-content">
          <div>
            <h1 className="page-title">{title}</h1>
            {subtitle && <p className="page-subtitle">{subtitle}</p>}
          </div>
          {action && <div className="page-action">{action}</div>}
        </div>
      </div>
      <div className="page-content">
        {children}
      </div>
    </div>
  );
}