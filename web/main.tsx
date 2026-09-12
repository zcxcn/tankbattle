import { createRoot } from 'react-dom/client';
import Home from '../app/page';
import '../app/globals.css';
import './mobile.css';
import './command.css';

createRoot(document.getElementById('root')!).render(<Home />);
