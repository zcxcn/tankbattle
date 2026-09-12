import { createRoot } from 'react-dom/client';
import Home from '../app/page';
import '../app/globals.css';
import './mobile.css';
import './command.css';
import './combat-hud.css';

createRoot(document.getElementById('root')!).render(<Home />);
