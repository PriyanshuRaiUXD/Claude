import { useEffect, useState } from 'react';
import { formatPrice, type ProductInfo } from '../../shared/catalog';
import { api } from '../lib/api';
import { prefs, session } from '../lib/storage';

const CHANNEL = 'loveseat-checkout';

function announce(roomId: string, status: 'paid' | 'cancelled' | 'pending'): void {
  try {
    const ch = new BroadcastChannel(CHANNEL);
    ch.postMessage({ roomId, status });
    ch.close();
  } catch {
    /* older browsers: the room still updates through its socket */
  }
}

/**
 * This tab was opened from the room tab, so the browser copied that tab's sessionStorage — including
 * its seat id. Forget it here, or "Back to the room" from this tab would evict the original tab.
 */
function forgetCopiedSeat(roomId: string): void {
  session.remove(`loveseat:client:${roomId}`);
}

/** Try to close the checkout tab. Browsers only allow it for some tabs, so the page also says so. */
function finish(): void {
  window.setTimeout(() => window.close(), 1600);
}

function BackLink({ roomId }: { roomId: string }) {
  return (
    <>
      <p className="muted small">You can close this tab — your room is still open in the other one.</p>
      <a className="btn btn-ghost" href={`/r/${roomId}`}>
        No other tab? Open the room here
      </a>
    </>
  );
}

/** Stripe's success/cancel landing page. */
export function CheckoutDone({ search }: { search: URLSearchParams }) {
  const roomId = search.get('room') ?? '';
  const sessionId = search.get('session_id');
  const cancelled = search.get('cancelled') === '1';
  const [status, setStatus] = useState<'checking' | 'paid' | 'pending' | 'cancelled' | 'error'>(cancelled ? 'cancelled' : 'checking');
  const [error, setError] = useState('');

  useEffect(() => {
    forgetCopiedSeat(roomId);
    if (cancelled) {
      announce(roomId, 'cancelled');
      finish();
      return;
    }
    if (!sessionId) {
      setStatus('error');
      setError('Missing checkout reference.');
      return;
    }
    let tries = 0;
    let stop = false;
    const check = async () => {
      try {
        const res = await api.verify(roomId, sessionId);
        if (stop) return;
        if (res.status === 'paid') {
          if (res.manageToken) prefs.setManageToken(roomId, res.manageToken);
          setStatus('paid');
          announce(roomId, 'paid');
          finish();
        } else if (res.status === 'pending' || tries++ < 5) {
          setStatus('pending');
          window.setTimeout(check, 2000);
        } else {
          setStatus('error');
          setError('Payment was not completed.');
        }
      } catch (err) {
        setStatus('error');
        setError((err as Error).message);
      }
    };
    void check();
    return () => {
      stop = true;
    };
  }, [cancelled, roomId, sessionId]);

  return (
    <div className="center-screen">
      <div className="card narrow center">
        {status === 'checking' && <h1>Confirming your payment…</h1>}
        {status === 'pending' && <h1>Almost there — waiting for your bank…</h1>}
        {status === 'paid' && (
          <>
            <h1>You’re all set ♥</h1>
            <p className="muted">It’s already unlocked in your room — for both of you.</p>
            <BackLink roomId={roomId} />
          </>
        )}
        {status === 'cancelled' && (
          <>
            <h1>No worries</h1>
            <p className="muted">Nothing was charged.</p>
            <BackLink roomId={roomId} />
          </>
        )}
        {status === 'error' && (
          <>
            <h1>Something went wrong</h1>
            <p className="error">{error}</p>
            <a className="btn btn-primary" href={`/r/${roomId}`}>
              Back to the room
            </a>
          </>
        )}
      </div>
    </div>
  );
}

/** Simulated checkout used when the server has no Stripe key. Makes every paid flow testable locally. */
export function DemoCheckout({ search }: { search: URLSearchParams }) {
  const token = search.get('t') ?? '';
  const manageRoom = search.get('manage');
  const [info, setInfo] = useState<{ roomId: string; product: ProductInfo } | null>(null);
  const [state, setState] = useState<'loading' | 'ready' | 'paying' | 'done' | 'error'>('loading');
  const [error, setError] = useState('');

  useEffect(() => {
    forgetCopiedSeat(manageRoom ?? '');
    if (manageRoom) return setState('ready');
    api
      .demoDescribe(token)
      .then((d) => {
        forgetCopiedSeat(d.roomId);
        setInfo(d);
        setState('ready');
      })
      .catch((err: Error) => {
        setError(err.message);
        setState('error');
      });
  }, [token, manageRoom]);

  if (manageRoom) {
    const manageToken = prefs.manageToken(manageRoom);
    return (
      <div className="center-screen">
        <div className="card narrow">
          <p className="demo-note">Demo billing portal — stands in for Stripe’s customer portal.</p>
          <h1>Couples Pro</h1>
          {state === 'done' ? (
            <p className="muted">Cancelled. The room is back on the free plan.</p>
          ) : (
            <button
              className="btn btn-ghost danger"
              disabled={!manageToken}
              onClick={async () => {
                try {
                  await api.demoCancel(manageRoom, manageToken!);
                  setState('done');
                  finish();
                } catch (err) {
                  setError((err as Error).message);
                }
              }}
            >
              Cancel subscription
            </button>
          )}
          {error && <p className="error">{error}</p>}
        </div>
      </div>
    );
  }

  return (
    <div className="center-screen">
      <div className="card narrow demo-checkout">
        <p className="demo-note">Demo checkout — no Stripe key is configured on this server, so no card is needed and nothing is charged. Add STRIPE_SECRET_KEY to use real Stripe Checkout.</p>
        {state === 'loading' && <p>Loading…</p>}
        {state === 'error' && <p className="error">{error}</p>}
        {info && state !== 'error' && (
          <>
            <h1>{info.product.name}</h1>
            <p className="muted">{info.product.description}</p>
            <p className="price">
              {formatPrice(info.product.amount, info.product.currency)}
              {info.product.recurring && <small> / month</small>}
            </p>
            {state === 'done' ? (
              <>
                <p>Paid ♥ It’s already unlocked in your room, for both of you.</p>
                <BackLink roomId={info.roomId} />
              </>
            ) : (
              <button
                className="btn btn-primary btn-lg"
                disabled={state === 'paying'}
                onClick={async () => {
                  setState('paying');
                  try {
                    const res = await api.demoComplete(token);
                    if (res.manageToken) prefs.setManageToken(res.roomId, res.manageToken);
                    setState('done');
                    announce(res.roomId, 'paid');
                    finish();
                  } catch (err) {
                    setError((err as Error).message);
                    setState('error');
                  }
                }}
              >
                {state === 'paying' ? 'Processing…' : `Pay ${formatPrice(info.product.amount, info.product.currency)} (simulated)`}
              </button>
            )}
          </>
        )}
      </div>
    </div>
  );
}
