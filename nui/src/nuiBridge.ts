const DEV_RESOURCE_NAME = '7-pmms';
const THROTTLED_NUI_MESSAGES: Record<string, number> = {
  seekToTime: 250,
  seekBackward: 250,
  seekForward: 250,
  setBaseVolume: 150,
  setVolume: 150,
  setRange: 400,
  setAttenuation: 400,
  setDiffRoomVolume: 400,
  setTransition: 400,
  setEqAnalyserActive: 250
};
const lastNuiMessageAt = new Map<string, number>();

function getMessageThrottleKey(name: string, data?: unknown): string {
  const handle = data && typeof data === 'object' && 'handle' in data ? (data as { handle?: unknown }).handle : 'global';
  return `${name}:${String(handle ?? 'global')}`;
}

function canSendNuiMessage(name: string, data?: unknown): boolean {
  const throttleMs = THROTTLED_NUI_MESSAGES[name];
  if (!throttleMs) {
    return true;
  }

  const now = Date.now();
  const key = getMessageThrottleKey(name, data);
  const lastSentAt = lastNuiMessageAt.get(key) || 0;
  if (now - lastSentAt < throttleMs) {
    return false;
  }

  lastNuiMessageAt.set(key, now);
  return true;
}

export function getResourceName(): string {
  if (typeof window.GetParentResourceName === 'function') {
    return window.GetParentResourceName();
  }

  return DEV_RESOURCE_NAME;
}

export function isFiveMRuntime(): boolean {
  return typeof window.GetParentResourceName === 'function';
}

export function sendNuiMessage(name: string, data?: unknown): Promise<unknown> {
  if (!name) {
    return Promise.resolve({});
  }

  if (!canSendNuiMessage(name, data)) {
    return Promise.resolve({ throttled: true });
  }

  return fetch(`https://${getResourceName()}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data || {})
  })
    .then((response) => response.json().catch(() => ({})))
    .catch(() => ({}));
}
