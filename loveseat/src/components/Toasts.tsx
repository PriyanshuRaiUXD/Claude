import { useCallback, useState } from 'react';

export interface Toast {
  id: number;
  text: string;
  tone?: 'info' | 'love' | 'warn';
  action?: { label: string; run: () => void };
}

let nextId = 1;

export function useToasts() {
  const [toasts, setToasts] = useState<Toast[]>([]);
  const dismiss = useCallback((id: number) => setToasts((t) => t.filter((x) => x.id !== id)), []);
  const push = useCallback(
    (text: string, opts: Omit<Toast, 'id' | 'text'> & { ms?: number } = {}) => {
      const id = nextId++;
      setToasts((t) => [...t.slice(-3), { id, text, tone: opts.tone, action: opts.action }]);
      window.setTimeout(() => dismiss(id), opts.ms ?? 4200);
    },
    [dismiss],
  );
  return { toasts, push, dismiss };
}

export function Toasts({ toasts, dismiss }: { toasts: Toast[]; dismiss: (id: number) => void }) {
  return (
    <div className="toasts" role="status" aria-live="polite">
      {toasts.map((t) => (
        <div key={t.id} className={`toast toast-${t.tone ?? 'info'}`}>
          <span>{t.text}</span>
          {t.action && (
            <button
              onClick={() => {
                t.action!.run();
                dismiss(t.id);
              }}
            >
              {t.action.label}
            </button>
          )}
        </div>
      ))}
    </div>
  );
}
