import { CheckoutDone, DemoCheckout } from './pages/Checkout';
import { Landing } from './pages/Landing';
import { Room } from './pages/Room';
import { useLocation } from './router';

export function App() {
  const { path, search } = useLocation();
  const room = path.match(/^\/r\/([a-zA-Z0-9]{8,32})\/?$/);
  if (room) return <Room key={room[1]} roomId={room[1]!} />;
  if (path === '/checkout/demo') return <DemoCheckout search={search} />;
  if (path === '/checkout/done') return <CheckoutDone search={search} />;
  return <Landing />;
}
