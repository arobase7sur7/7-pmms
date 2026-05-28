import React, { createContext, useContext, useId, useMemo, useState } from 'react';
import { AnimatePresence, motion, type HTMLMotionProps, type Transition } from 'motion/react';
import { cn } from '../../../lib/utils';
import { usePmmsMotion } from '../../../motion/MotionProvider';

type TabsContextValue = {
  id: string;
  value: string;
  setValue: (value: string) => void;
  transition: Transition;
};

const TabsContext = createContext<TabsContextValue | null>(null);

function useTabsContext() {
  const value = useContext(TabsContext);
  if (!value) {
    throw new Error('Tabs components must be used inside Tabs');
  }
  return value;
}

export type TabsProps = Omit<React.ComponentProps<'div'>, 'onChange'> & {
  value?: string;
  defaultValue?: string;
  onValueChange?: (value: string) => void;
  transition?: Transition;
};

export function Tabs({ value, defaultValue = '', onValueChange, transition, className, ...props }: TabsProps) {
  const generatedId = useId();
  const motion = usePmmsMotion();
  const [internalValue, setInternalValue] = useState(defaultValue);
  const currentValue = value ?? internalValue;
  const resolvedTransition = transition ?? motion.spring;

  const contextValue = useMemo<TabsContextValue>(() => ({
    id: generatedId.replace(/:/g, ''),
    value: currentValue,
    transition: resolvedTransition,
    setValue: (nextValue: string) => {
      if (value === undefined) setInternalValue(nextValue);
      onValueChange?.(nextValue);
    },
  }), [currentValue, generatedId, onValueChange, resolvedTransition, value]);

  return (
    <TabsContext.Provider value={contextValue}>
      <div className={cn('animate-ui-tabs', className)} {...props} />
    </TabsContext.Provider>
  );
}

export type TabsListProps = React.ComponentProps<'div'>;

export function TabsList({ className, ...props }: TabsListProps) {
  return <div role="tablist" className={cn('animate-ui-tabs-list', className)} {...props} />;
}

export type TabsTriggerProps = Omit<HTMLMotionProps<'button'>, 'value' | 'onChange' | 'children'> & {
  value: string;
  children?: React.ReactNode;
};

export function TabsTrigger({ value, className, children, onClick, ...props }: TabsTriggerProps) {
  const tabs = useTabsContext();
  const active = tabs.value === value;

  return (
    <motion.button
      type="button"
      role="tab"
      aria-selected={active}
      data-state={active ? 'active' : 'inactive'}
      className={cn('animate-ui-tabs-trigger', className)}
      whileHover={{ x: 2 }}
      whileTap={{ scale: 0.985 }}
      transition={tabs.transition}
      onClick={(event) => {
        tabs.setValue(value);
        onClick?.(event);
      }}
      {...props}
    >
      <AnimatePresence initial={false}>
        {active && (
          <motion.span
            aria-hidden="true"
            className="animate-ui-tabs-highlight"
            layoutId={`tabs-highlight-${tabs.id}`}
            transition={tabs.transition}
          />
        )}
      </AnimatePresence>
      <span className="animate-ui-tabs-trigger-content">
        {children}
      </span>
    </motion.button>
  );
}

export type TabsContentsProps = React.ComponentProps<'div'>;

export function TabsContents({ className, ...props }: TabsContentsProps) {
  return <div className={cn('animate-ui-tabs-contents', className)} {...props} />;
}

export type TabsContentProps = Omit<HTMLMotionProps<'div'>, 'children'> & {
  value: string;
  children?: React.ReactNode;
};

export function TabsContent({ value, className, children, ...props }: TabsContentProps) {
  const tabs = useTabsContext();
  const motionConfig = usePmmsMotion();
  const active = tabs.value === value;

  return (
    <AnimatePresence mode="wait" initial={false}>
      {active && (
        <motion.div
          role="tabpanel"
          className={cn('animate-ui-tabs-content', className)}
          initial={{ opacity: 0, y: motionConfig.reducedMotion ? 0 : 8 }}
          animate={{ opacity: 1, y: 0 }}
          exit={{ opacity: 0, y: motionConfig.reducedMotion ? 0 : -6 }}
          transition={tabs.transition}
          {...props}
        >
          {children}
        </motion.div>
      )}
    </AnimatePresence>
  );
}

export function TabsHighlight({ children }: { children: React.ReactNode }) {
  return <>{children}</>;
}

export function TabsHighlightItem({ children }: { children: React.ReactNode; value?: string }) {
  return <>{children}</>;
}
