/// <reference types="vite/client" />

declare global {
  interface Window {
    GetParentResourceName?: () => string;
  }
}

export {};
