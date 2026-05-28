import React, { createContext, useContext, useEffect, useMemo, useState } from 'react';
import { motion, useMotionValue, useSpring, type HTMLMotionProps } from 'motion/react';
import { cn } from '../../../lib/utils';
import { usePmmsMotion } from '../../../motion/MotionProvider';

type CursorContextValue = {
  active: boolean;
  x: ReturnType<typeof useSpring>;
  y: ReturnType<typeof useSpring>;
};

const CursorContext = createContext<CursorContextValue | null>(null);

function useCursorContext() {
  const value = useContext(CursorContext);
  if (!value) {
    throw new Error('Cursor components must be used inside CursorProvider');
  }
  return value;
}

function isInteractiveTextTarget(target: EventTarget | null) {
  if (!(target instanceof Element)) return false;
  return !!target.closest('input, textarea, select, [contenteditable="true"]');
}

export type CursorProviderProps = {
  children: React.ReactNode;
  disabled?: boolean;
  global?: boolean;
};

export function CursorProvider({ children, disabled, global = false }: CursorProviderProps) {
  const motionConfig = usePmmsMotion();
  const x = useMotionValue(-100);
  const y = useMotionValue(-100);
  const springX = useSpring(x, { stiffness: 520, damping: 46, mass: 0.55 });
  const springY = useSpring(y, { stiffness: 520, damping: 46, mass: 0.55 });
  const [active, setActive] = useState(false);
  const [coarsePointer, setCoarsePointer] = useState(false);
  const [draggingRange, setDraggingRange] = useState(false);

  useEffect(() => {
    const media = window.matchMedia('(pointer: coarse)');
    const sync = () => setCoarsePointer(media.matches);
    sync();
    media.addEventListener?.('change', sync);
    return () => media.removeEventListener?.('change', sync);
  }, []);

  const suspended = !!disabled || motionConfig.reducedMotion || coarsePointer || draggingRange;

  useEffect(() => {
    if (suspended) {
      setActive(false);
      return undefined;
    }

    const root = global ? document : document.getElementById('app-container');
    if (!root) return undefined;

    let frame = 0;
    const move = (event: Event) => {
      const pointer = event as PointerEvent;
      if (isInteractiveTextTarget(pointer.target)) {
        setActive(false);
        return;
      }

      if (frame) cancelAnimationFrame(frame);
      frame = requestAnimationFrame(() => {
        x.set(pointer.clientX - 5);
        y.set(pointer.clientY - 5);
        setActive(true);
      });
    };

    const leave = () => setActive(false);
    const pointerDown = (event: Event) => {
      const target = event.target;
      if (target instanceof HTMLInputElement && target.type === 'range') {
        setDraggingRange(true);
      }
    };
    const pointerUp = () => setDraggingRange(false);

    root.addEventListener('pointermove', move, { passive: true });
    root.addEventListener('pointerleave', leave);
    document.addEventListener('pointerdown', pointerDown, { passive: true });
    document.addEventListener('pointerup', pointerUp, { passive: true });

    return () => {
      if (frame) cancelAnimationFrame(frame);
      root.removeEventListener('pointermove', move);
      root.removeEventListener('pointerleave', leave);
      document.removeEventListener('pointerdown', pointerDown);
      document.removeEventListener('pointerup', pointerUp);
    };
  }, [global, suspended, x, y]);

  const value = useMemo(() => ({ active, x: springX, y: springY }), [active, springX, springY]);

  return (
    <CursorContext.Provider value={value}>
      {children}
    </CursorContext.Provider>
  );
}

export type CursorProps = HTMLMotionProps<'div'>;

export function Cursor({ className, ...props }: CursorProps) {
  const cursor = useCursorContext();
  return (
    <motion.div
      aria-hidden="true"
      className={cn('animate-ui-cursor', className)}
      style={{ x: cursor.x, y: cursor.y }}
      animate={{ opacity: cursor.active ? 1 : 0, scale: cursor.active ? 1 : 0.7 }}
      transition={{ type: 'spring', stiffness: 500, damping: 40 }}
      {...props}
    />
  );
}

export type CursorFollowProps = HTMLMotionProps<'div'>;

export function CursorFollow({ className, children, ...props }: CursorFollowProps) {
  const cursor = useCursorContext();
  return (
    <motion.div
      aria-hidden="true"
      className={cn('animate-ui-cursor-follow', className)}
      style={{ x: cursor.x, y: cursor.y }}
      animate={{ opacity: cursor.active ? 1 : 0, scale: cursor.active ? 1 : 0.86 }}
      transition={{ type: 'spring', stiffness: 360, damping: 34 }}
      {...props}
    >
      {children}
    </motion.div>
  );
}

export type CursorContainerProps = React.ComponentProps<'div'>;

export function CursorContainer({ children, className, ...props }: CursorContainerProps) {
  return (
    <div className={cn('animate-ui-cursor-container', className)} {...props}>
      {children}
    </div>
  );
}
