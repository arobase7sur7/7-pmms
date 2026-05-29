import React, { useEffect, useState } from 'react';
import { createPortal } from 'react-dom';
import { AnimatePresence, motion } from 'motion/react';
import { usePmmsMotion } from './MotionProvider';

type TooltipState = {
  text: string;
  x: number;
  y: number;
  key: number;
};

function getTooltipElement(target: EventTarget | null) {
  if (!(target instanceof Element)) return null;
  return target.closest<HTMLElement>('[data-tooltip], [title]');
}

function getTooltipText(target: EventTarget | null) {
  const element = getTooltipElement(target);
  if (!element) return '';
  const title = element.getAttribute('title') || '';
  if (title) {
    element.setAttribute('data-tooltip', title);
    if (!element.getAttribute('aria-label')) element.setAttribute('aria-label', title);
    element.removeAttribute('title');
  }
  return element.getAttribute('data-tooltip') || title;
}

function getAnchorRect(target: EventTarget | null) {
  const element = getTooltipElement(target);
  return element?.getBoundingClientRect() || null;
}

function getTooltipPoint(event: Event, rect: DOMRect) {
  const padding = 12;
  const isPointer = event instanceof MouseEvent;
  const x = isPointer ? event.clientX : rect.left + rect.width / 2;
  const y = isPointer ? event.clientY - 14 : rect.top - 10;
  return {
    x: Math.min(Math.max(x, padding), window.innerWidth - padding),
    y: Math.min(Math.max(y, 42), window.innerHeight - padding),
  };
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
      const point = getTooltipPoint(event, rect);

      setTooltip({
        text,
        x: point.x,
        y: point.y,
        key: ++seq,
      });
    };

    const hide = (event?: Event) => {
      if (event instanceof MouseEvent) {
        const element = getTooltipElement(event.target);
        if (element && event.relatedTarget instanceof Node && element.contains(event.relatedTarget)) return;
      }
      setTooltip(null);
    };
    const move = (event: MouseEvent) => {
      const text = getTooltipText(event.target);
      if (!text) return;
      const rect = getAnchorRect(event.target);
      if (!rect) return;
      const point = getTooltipPoint(event, rect);
      setTooltip(previous => previous ? { ...previous, x: point.x, y: point.y } : previous);
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

  return createPortal(
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
    </AnimatePresence>,
    document.body,
  );
}
