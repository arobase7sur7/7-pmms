const DEV_RESOURCE_NAME = '7-pmms';

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

  return fetch(`https://${getResourceName()}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data || {})
  })
    .then((response) => response.json().catch(() => ({})))
    .catch(() => ({}));
}
