import { createRoot } from 'react-dom/client';
import Home from '../app/page';
import '../app/globals.css';
import './mobile.css';

createRoot(document.getElementById('root')!).render(<Home />);
