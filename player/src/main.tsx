import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import Player from './Player';

createRoot(document.getElementById('root') as HTMLElement).render(
  <StrictMode>
    <Player />
  </StrictMode>,
);
