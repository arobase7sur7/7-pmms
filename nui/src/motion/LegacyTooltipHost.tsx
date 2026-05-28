import React, { useEffect, useState } from 'react';
import { AnimatePresence, motion } from 'motion/react';
import { usePmmsMotion } from './MotionProvider';

type TooltipState = {
  text: string;
  x: number;
  y: number;
  key: number;
};

function getTooltipText(target: EventTarget | null) {
  if (!(target instanceof Element)) return '';
  const element = target.closest<HTMLElement>('[data-tooltip]');
  return element?.getAttribute('data-tooltip') || '';
}

function getAnchorRect(target: EventTarget | null) {
  if (!(target instanceof Element)) return null;
  const element = target.closest<HTMLElement>('[data-tooltip]');
  return element?.getBoundingClientRect() || null;
}

export function LegacyTooltipHost() {
  const motionConfig = usePmmsMotion();
  const [tooltip, setTooltip] = useState<TooltipState | null>(null);

  useEffect(() => {
    let seq = 0;

    const show = (event: Event) => {
      if (motionConfig.reducedMotion) return;
      const text = getTooltipText(event.target);
      const rect = getAnchorRect(event.target);
      if (!text || !rect) return;

      setTooltip({
        text,
        x: rect.left + rect.width / 2,
        y: rect.top - 10,
        key: ++seq,
      });
    };

    const hide = () => setTooltip(null);
    const move = (event: MouseEvent) => {
      const text = getTooltipText(event.target);
      if (!text) return;
      setTooltip(previous => previous ? { ...previous, x: event.clientX, y: event.clientY - 16 } : previous);
    };

    document.addEventListener('mouseover', show, true);
    document.addEventListener('focusin', show, true);
    document.addEventListener('mouseout', hide, true);
    document.addEventListener('focusout', hide, true);
    document.addEventListener('mousedown', hide, true);
    document.addEventListener('scroll', hide, true);
    document.addEventListener('mousemove', move, { passive: true });

    return () => {
      document.removeEventListener('mouseover', show, true);
      document.removeEventListener('focusin', show, true);
      document.removeEventListener('mouseout', hide, true);
      document.removeEventListener('focusout', hide, true);
      document.removeEventListener('mousedown', hide, true);
      document.removeEventListener('scroll', hide, true);
      document.removeEventListener('mousemove', move);
    };
  }, [motionConfig.reducedMotion]);

  return (
    <AnimatePresence>
      {tooltip && motionConfig.uiVisible && (
        <motion.div
          key={tooltip.key}
          className="pmms-motion-tooltip"
          style={{ left: tooltip.x, top: tooltip.y }}
          initial={{ opacity: 0, scale: 0.94 }}
          animate={{ opacity: 1, scale: 1 }}
          exit={{ opacity: 0, scale: 0.94 }}
          transition={motionConfig.popSpring}
        >
          {tooltip.text}
        </motion.div>
      )}
    </AnimatePresence>
  );
}
