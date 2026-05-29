import fs from 'node:fs';

let passed = 0;
let failed = 0;

function assert(label, ok, note = '') {
  if (ok) {
    console.log(`  PASS  ${label}`);
    passed += 1;
    return;
  }
  console.error(`  FAIL  ${label}  ${note}`);
  failed += 1;
}

function isTypedArray(value) {
  return ArrayBuffer.isView(value) && !(value instanceof DataView);
}

function shallowEqualStableValue(left, right) {
  if (Object.is(left, right)) return true;

  if (isTypedArray(left) && isTypedArray(right)) {
    if (left.length !== right.length) return false;
    for (let index = 0; index < left.length; index += 1) {
      if (!Object.is(left[index], right[index])) return false;
    }
    return true;
  }

  if (!left || !right || typeof left !== 'object' || typeof right !== 'object') {
    return false;
  }

  if (Array.isArray(left) && Array.isArray(right)) {
    if (left.length !== right.length) return false;
    for (let index = 0; index < left.length; index += 1) {
      if (!Object.is(left[index], right[index])) return false;
    }
    return true;
  }

  const leftKeys = Object.keys(left);
  const rightKeys = Object.keys(right);
  if (leftKeys.length !== rightKeys.length) return false;
  return leftKeys.every((key) => Object.prototype.hasOwnProperty.call(right, key) && Object.is(left[key], right[key]));
}

function renderCounter(initialState) {
  let state = initialState;
  let renders = 1;
  return {
    set(nextState) {
      const resolved = typeof nextState === 'function' ? nextState(state) : nextState;
      if (!shallowEqualStableValue(state, resolved)) {
        state = resolved;
        renders += 1;
      }
    },
    get renders() {
      return renders;
    }
  };
}

console.log('\n[Stable state]');
const objectState = renderCounter({ viewId: 'home', count: 1 });
objectState.set({ viewId: 'home', count: 1 });
objectState.set({ viewId: 'home', count: 2 });
assert('Identical shallow object skips one render', objectState.renders === 2, `renders=${objectState.renders}`);

const analyserState = renderCounter(new Float32Array([0.1, 0.2, 0.3]));
analyserState.set(new Float32Array([0.1, 0.2, 0.3]));
analyserState.set(new Float32Array([0.1, 0.2, 0.4]));
assert('Identical analyser bins skip one render', analyserState.renders === 2, `renders=${analyserState.renders}`);

const arrayState = renderCounter(['home', 'library']);
arrayState.set(['home', 'library']);
arrayState.set(['home', 'admin']);
assert('Identical arrays skip one render', arrayState.renders === 2, `renders=${arrayState.renders}`);

console.log('\n[Source guards]');
const hook = fs.readFileSync('nui/src/useStableState.ts', 'utf8');
const app = fs.readFileSync('nui/src/App.tsx', 'utf8');
const admin = fs.readFileSync('nui/src/AdminView.tsx', 'utf8');
const main = fs.readFileSync('client/main.lua', 'utf8');
const dui = fs.readFileSync('client/dui.lua', 'utf8');
const serverMain = fs.readFileSync('server/main.lua', 'utf8');

assert('useStableState hook exists', /export function useStableState/.test(hook));
assert('Hook compares typed arrays', /ArrayBuffer\.isView/.test(hook));
assert('App uses stable state for analyser data', /useStableState<Float32Array \| null>/.test(app));
assert('Sidebar nav items are memoized', /const navItems = useMemo/.test(app));
assert('Sidebar view change handler is stable', /const handleViewChange = useCallback/.test(app));
assert('Admin data uses stable state', /const \[adminData, setAdminData\] = useStableState/.test(admin));
assert('Admin device selection handler is stable', /const selectDevice = useCallback/.test(admin));
assert('Admin lists are memoized', /const unifiedDevices = useMemo/.test(admin) && /const filteredDevices = useMemo/.test(admin));
assert('Client main loop keeps relaxed UI wait', /selectedHandle ~= nil and 250 or 500/.test(main));
assert('DUI keeps 30fps active cap', /renderMaxFps",\s*30,\s*5,\s*30/.test(dui));
assert('Server sync throttle keeps one-second debounce', /SYNC_THROTTLE_MS\s*=\s*1000/.test(serverMain));

console.log(`\nResults: ${passed} passed, ${failed} failed`);
process.exit(failed > 0 ? 1 : 0);
