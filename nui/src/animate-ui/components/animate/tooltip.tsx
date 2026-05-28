import React, { createContext, useContext, useState } from 'react';
import {
  autoUpdate,
  flip,
  offset,
  shift,
  useDismiss,
  useFloating,
  useFocus,
  useHover,
  useInteractions,
  type Placement,
} from '@floating-ui/react';
import { AnimatePresence, motion, type Transition } from 'motion/react';
import { cn } from '../../../lib/utils';
import { usePmmsMotion } from '../../../motion/MotionProvider';

type TooltipContextValue = {
  open: boolean;
  refs: ReturnType<typeof useFloating>['refs'];
  floatingStyles: React.CSSProperties;
  getReferenceProps: ReturnType<typeof useInteractions>['getReferenceProps'];
  getFloatingProps: ReturnType<typeof useInteractions>['getFloatingProps'];
  transition: Transition;
};

const TooltipContext = createContext<TooltipContextValue | null>(null);

function useTooltipContext() {
  const value = useContext(TooltipContext);
  if (!value) {
    throw new Error('Tooltip components must be used inside Tooltip');
  }
  return value;
}

export type TooltipProviderProps = {
  children: React.ReactNode;
  openDelay?: number;
};

export function TooltipProvider({ children }: TooltipProviderProps) {
  return <>{children}</>;
}

export type TooltipProps = {
  children: React.ReactNode;
  side?: Placement;
  sideOffset?: number;
  delayDuration?: number;
  transition?: Transition;
};

export function Tooltip({ children, side = 'top', sideOffset = 10, delayDuration = 0, transition }: TooltipProps) {
  const motionConfig = usePmmsMotion();
  const [open, setOpen] = useState(false);
  const floating = useFloating({
    open,
    onOpenChange: setOpen,
    placement: side,
    whileElementsMounted: autoUpdate,
    middleware: [offset(sideOffset), flip(), shift({ padding: 10 })],
  });
  const hover = useHover(floating.context, { delay: { open: delayDuration, close: 80 } });
  const focus = useFocus(floating.context);
  const dismiss = useDismiss(floating.context);
  const interactions = useInteractions([hover, focus, dismiss]);

  return (
    <TooltipContext.Provider
      value={{
        open,
        refs: floating.refs,
        floatingStyles: floating.floatingStyles,
        getReferenceProps: interactions.getReferenceProps,
        getFloatingProps: interactions.getFloatingProps,
        transition: transition ?? motionConfig.popSpring,
      }}
    >
      {children}
    </TooltipContext.Provider>
  );
}

export type TooltipTriggerProps = React.ComponentProps<'span'> & {
  asChild?: boolean;
};

export function TooltipTrigger({ asChild, children, ...props }: TooltipTriggerProps) {
  const tooltip = useTooltipContext();

  if (asChild && React.isValidElement(children)) {
    return React.cloneElement(children as React.ReactElement, {
      ref: tooltip.refs.setReference,
      ...tooltip.getReferenceProps({
        ...(children.props || {}),
        ...props,
      }),
    });
  }

  return (
    <span ref={tooltip.refs.setReference} {...tooltip.getReferenceProps(props)}>
      {children}
    </span>
  );
}

export type TooltipContentProps = {
  children: React.ReactNode;
  className?: string;
};

export function TooltipContent({ className, children }: TooltipContentProps) {
  const tooltip = useTooltipContext();

  return (
    <AnimatePresence>
      {tooltip.open && (
        <motion.div
          ref={tooltip.refs.setFloating}
          className={cn('pmms-motion-tooltip', className)}
          style={tooltip.floatingStyles}
          initial={{ opacity: 0, scale: 0.96 }}
          animate={{ opacity: 1, scale: 1 }}
          exit={{ opacity: 0, scale: 0.96 }}
          transition={tooltip.transition}
          {...tooltip.getFloatingProps()}
        >
          {children}
        </motion.div>
      )}
    </AnimatePresence>
  );
}
