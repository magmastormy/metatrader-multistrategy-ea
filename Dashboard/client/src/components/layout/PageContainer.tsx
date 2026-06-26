import type { ReactNode } from 'react';

interface PageContainerProps {
  title: string;
  children: ReactNode;
}

export default function PageContainer({ title, children }: PageContainerProps) {
  return (
    <div className="animate-fade-in p-4 h-full overflow-auto">
      <h2 className="text-xl font-bold text-text mb-4 tracking-tight">
        {title}
      </h2>
      {children}
    </div>
  );
}
