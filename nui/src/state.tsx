import { createContext, useContext, useMemo, useReducer, type Dispatch, type ReactNode } from 'react';

type AppState = {
  mounted: boolean;
};

type AppAction = {
  type: 'legacy-mounted';
};

const initialState: AppState = {
  mounted: false
};

function reducer(state: AppState, action: AppAction): AppState {
  switch (action.type) {
    case 'legacy-mounted':
      return state.mounted ? state : { ...state, mounted: true };
    default:
      return state;
  }
}

type AppStateContextValue = {
  state: AppState;
  dispatch: Dispatch<AppAction>;
};

const AppStateContext = createContext<AppStateContextValue | null>(null);

export function AppStateProvider({ children }: { children: ReactNode }) {
  const [state, dispatch] = useReducer(reducer, initialState);
  const value = useMemo(() => ({ state, dispatch }), [state]);

  return <AppStateContext.Provider value={value}>{children}</AppStateContext.Provider>;
}

export function useAppState() {
  const context = useContext(AppStateContext);
  if (!context) {
    throw new Error('useAppState must be used within AppStateProvider');
  }
  return context;
}
