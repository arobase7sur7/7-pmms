import { Dispatch, SetStateAction, useCallback, useState } from 'react';

function isTypedArray(value: unknown): value is ArrayLike<number> {
  return ArrayBuffer.isView(value) && !(value instanceof DataView);
}

function shallowEqualArrayLike(left: ArrayLike<number>, right: ArrayLike<number>): boolean {
  if (left.length !== right.length) {
    return false;
  }

  for (let index = 0; index < left.length; index += 1) {
    if (!Object.is(left[index], right[index])) {
      return false;
    }
  }

  return true;
}

function shallowEqualObject(left: Record<string, unknown>, right: Record<string, unknown>): boolean {
  const leftKeys = Object.keys(left);
  const rightKeys = Object.keys(right);
  if (leftKeys.length !== rightKeys.length) {
    return false;
  }

  for (const key of leftKeys) {
    if (!Object.prototype.hasOwnProperty.call(right, key) || !Object.is(left[key], right[key])) {
      return false;
    }
  }

  return true;
}

export function shallowEqualStableValue<T>(left: T, right: T): boolean {
  if (Object.is(left, right)) {
    return true;
  }

  if (isTypedArray(left) && isTypedArray(right)) {
    return shallowEqualArrayLike(left, right);
  }

  if (!left || !right || typeof left !== 'object' || typeof right !== 'object') {
    return false;
  }

  if (Array.isArray(left) && Array.isArray(right)) {
    return shallowEqualArrayLike(left, right);
  }

  return shallowEqualObject(left as Record<string, unknown>, right as Record<string, unknown>);
}

export function useStableState<T>(initialState: T | (() => T)): [T, Dispatch<SetStateAction<T>>] {
  const [state, setState] = useState<T>(initialState);
  const setStableState = useCallback<Dispatch<SetStateAction<T>>>((nextState) => {
    setState((currentState) => {
      const resolvedState = typeof nextState === 'function'
        ? (nextState as (current: T) => T)(currentState)
        : nextState;
      return shallowEqualStableValue(currentState, resolvedState) ? currentState : resolvedState;
    });
  }, []);

  return [state, setStableState];
}
