export function initLegacyUi(): void;

export const legacyActions: {
  switchView(viewId: string): void;
  sendMessage(name: string, data?: unknown): void;
  openCreatePlaylist(): void;
  playPlaylist(): void;
  deleteCurrentPlaylist(): void;
  sendFriendRequest(): void;
  closeAdminModal(): void;
};
