import { useState } from 'react';
import { PLANS, formatPrice } from '../../shared/catalog';
import { IconFilm, IconGift, IconHeart, IconScreen } from '../components/Icons';
import { api } from '../lib/api';
import { navigate } from '../router';

export function Landing() {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const create = async () => {
    setBusy(true);
    setError(null);
    try {
      const { id } = await api.createRoom();
      navigate(`/r/${id}`);
    } catch (err) {
      setError((err as Error).message);
      setBusy(false);
    }
  };

  return (
    <div className="landing">
      <header className="landing-nav">
        <span className="brand">
          <IconHeart width={18} height={18} /> Loveseat
        </span>
      </header>

      <section className="hero">
        <h1>
          Same couch.
          <br />
          Different cities.
        </h1>
        <p className="hero-sub">
          A private living room for the two of you. Share any tab — Netflix, YouTube, the big game — with real stereo sound, and keep each other’s faces floating
          right there on the screen.
        </p>
        <button className="btn btn-primary btn-xl" onClick={create} disabled={busy}>
          {busy ? 'Opening…' : 'Open our living room'}
        </button>
        <p className="muted small">No account. No download. Send one link.</p>
        {error && <p className="error">{error}</p>}
      </section>

      <section className="features">
        <div className="feature">
          <IconScreen />
          <h3>Any site, any app</h3>
          <p>Share a browser tab, a window or your whole screen. If you can watch it, you can watch it together.</p>
        </div>
        <div className="feature">
          <IconFilm />
          <h3>Cinema mode</h3>
          <p>Nothing on screen but the movie and your person. Controls appear when you move the mouse and vanish when you don’t.</p>
        </div>
        <div className="feature">
          <IconGift />
          <h3>Little gestures</h3>
          <p>Clink champagne, toss popcorn, set off fireworks — on both screens at the same moment.</p>
        </div>
      </section>

      <section className="pricing">
        <div className="price-card">
          <h3>Free</h3>
          <p className="price">$0</p>
          <ul>
            <li>720p / 30fps</li>
            <li>60-minute sessions</li>
            <li>Floating hearts, always free</li>
          </ul>
        </div>
        <div className="price-card">
          <h3>{PLANS.pass.name}</h3>
          <p className="price">
            {formatPrice(PLANS.pass.amount)} <small>once</small>
          </p>
          <ul>
            {PLANS.pass.perks.map((p) => (
              <li key={p}>{p}</li>
            ))}
          </ul>
        </div>
        <div className="price-card is-featured">
          <h3>{PLANS.pro.name}</h3>
          <p className="price">
            {formatPrice(PLANS.pro.amount)} <small>/ month</small>
          </p>
          <ul>
            {PLANS.pro.perks.map((p) => (
              <li key={p}>{p}</li>
            ))}
          </ul>
          <p className="muted small">One plan covers both of you.</p>
        </div>
      </section>

      <footer className="landing-foot muted small">
        Video and sound travel directly between your two browsers. Loveseat never sees or stores what you watch.
      </footer>
    </div>
  );
}
