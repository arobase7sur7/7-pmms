import React from 'react';
import { motion, type HTMLMotionProps } from 'motion/react';

type AnimateSlotProps = HTMLMotionProps<'span'> & {
  asChild?: boolean;
  children?: React.ReactNode;
};

export function AnimateSlot({ asChild, children, ...props }: AnimateSlotProps) {
  if (asChild && React.isValidElement(children)) {
    return React.cloneElement(children as React.ReactElement, {
      ...props,
      ...(children.props || {}),
    });
  }

  return (
    <motion.span {...props}>
      {children}
    </motion.span>
  );
}
