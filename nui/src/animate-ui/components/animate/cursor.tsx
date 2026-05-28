import React from 'react';
import {
  CursorProvider as CursorProviderPrimitive,
  Cursor as CursorPrimitive,
  CursorFollow as CursorFollowPrimitive,
  type CursorProviderProps,
  type CursorProps,
  type CursorFollowProps,
} from '../../primitives/animate/cursor';
import { cn } from '../../../lib/utils';

function CursorProvider(props: CursorProviderProps) {
  return <CursorProviderPrimitive {...props} />;
}

function Cursor({ className, ...props }: CursorProps) {
  return <CursorPrimitive className={cn('pmms-light-cursor', className)} {...props} />;
}

function CursorFollow({ className, children, ...props }: CursorFollowProps) {
  return (
    <CursorFollowPrimitive className={cn('pmms-light-cursor-follow', className)} {...props}>
      {children}
    </CursorFollowPrimitive>
  );
}

export {
  CursorProvider,
  Cursor,
  CursorFollow,
  type CursorProviderProps,
  type CursorProps,
  type CursorFollowProps,
};
