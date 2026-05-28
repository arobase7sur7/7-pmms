import React from 'react';
import { Cursor, CursorFollow, CursorProvider } from '../animate-ui/components/animate/cursor';
import { usePmmsMotion } from './MotionProvider';

export function MotionCursor() {
  const motionConfig = usePmmsMotion();
  const enabled = motionConfig.uiVisible && !motionConfig.reducedMotion;

  return (
    <CursorProvider disabled={!enabled}>
      <Cursor />
      <CursorFollow>
        <span />
      </CursorFollow>
    </CursorProvider>
  );
}
