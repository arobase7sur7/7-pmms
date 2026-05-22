import React, { StrictMode, useEffect } from 'react';
import ReactDOM from 'react-dom';
import { App } from './App';
import { installDevMock } from './devMock';
import { initLegacyUi } from './legacy/controller';
import './styles.css';

function Bootstrap() {
  useEffect(() => {
    initLegacyUi();
    installDevMock();
  }, []);

  return <App />;
}

const rootElement = document.getElementById('root');

if (!rootElement) {
  throw new Error('Missing #root element');
}

ReactDOM.render(
  <StrictMode>
    <Bootstrap />
  </StrictMode>,
  rootElement
);
