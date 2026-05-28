import React, { createContext, useContext, useEffect, useMemo, useState } from 'react';
import { useReducedMotion, type Transition } from 'motion/react';

type DeviceTheme = 'none' | 'speaker' | 'vehicle' | 'screen' | 'interaction';

type PmmsMotionContextValue = {
  reducedMotion: boolean;
  uiVisible: boolean;
  deviceTheme: DeviceTheme;
  spring: Transition;
  popSpring: Transition;
  softSpring: Transition;
};

const PmmsMotionContext = createContext<PmmsMotionContextValue | null>(null);

function readBodyState() {
  if (typeof document === 'undefined' || !document.body) {
    return { uiVisible: false, deviceTheme: 'none' as DeviceTheme };
  }

  const rawTheme = document.body.getAttribute('data-pmms-device-theme') as DeviceTheme | null;
  const deviceTheme: DeviceTheme = rawTheme || 'none';
  return {
    uiVisible: document.body.classList.contains('pmms-ui-visible'),
    deviceTheme,
  };
}

export function MotionProvider({ children }: { children: React.ReactNode }) {
  const prefersReducedMotion = useReducedMotion();
  const [bodyState, setBodyState] = useState(readBodyState);

  useEffect(() => {
    if (!document.body) return undefined;

    const sync = () => setBodyState(readBodyState());
    sync();

    const observer = new MutationObserver(sync);
    observer.observe(document.body, {
      attributes: true,
      attributeFilter: ['class', 'data-pmms-device-theme'],
    });

    window.addEventListener('pmms:motionStateChanged', sync);
    return () => {
      observer.disconnect();
      window.removeEventListener('pmms:motionStateChanged', sync);
    };
  }, []);

  const reducedMotion = prefersReducedMotion === true;

  const value = useMemo<PmmsMotionContextValue>(() => ({
    ...bodyState,
    reducedMotion,
    spring: reducedMotion
      ? { duration: 0.01 }
      : { type: 'spring', stiffness: 360, damping: 34, mass: 0.8 },
    popSpring: reducedMotion
      ? { duration: 0.01 }
      : { type: 'spring', stiffness: 420, damping: 28, mass: 0.75 },
    softSpring: reducedMotion
      ? { duration: 0.01 }
      : { type: 'spring', stiffness: 220, damping: 24, mass: 0.9 },
  }), [bodyState, reducedMotion]);

  return (
    <PmmsMotionContext.Provider value={value}>
      {children}
    </PmmsMotionContext.Provider>
  );
}

export function usePmmsMotion() {
  const value = useContext(PmmsMotionContext);
  if (!value) {
    throw new Error('usePmmsMotion must be used inside MotionProvider');
  }
  return value;
}
