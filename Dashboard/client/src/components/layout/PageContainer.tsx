import type { ReactNode } from 'react';

interface PageContainerProps {
  title: string;
  children: ReactNode;
}

export default function PageContainer({ title, children }: PageContainerProps) {
  return (
    <div className="animate-fade-in p-6 h-full overflow-auto">
      <h2 className="text-xl font-bold text-text-primary mb-6 tracking-tight">
        {title}
      </h2>
      {children}
    </div>
  );
}
