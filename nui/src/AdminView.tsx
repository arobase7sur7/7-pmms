import React, { useEffect, useMemo, useState } from 'react';
import { sendNuiMessage } from './nuiBridge';

interface PropModel {
  model: string;
  label: string;
  isTv?: boolean;
}

interface JobOption {
  name: string;
  label?: string;
}

interface ConfirmState {
  title: string;
  message: string;
  action: () => void;
}

function PropImage({ model, size = 48 }: { model: string; size?: number }) {
  const [idx, setIdx] = useState(0);
  const exts = ['png', 'jpg', 'webp', 'svg'];
  const src = idx >= exts.length
    ? './assets/props/fallback.svg'
    : `./assets/props/${model}.${exts[idx]}`;

  useEffect(() => {
    setIdx(0);
  }, [model]);

  return (
    <img
      src={src}
      alt={model}
      onError={() => setIdx(i => i + 1)}
      style={{ width: size, height: size, objectFit: 'contain', borderRadius: 4, background: 'rgba(255,255,255,0.04)', flexShrink: 0 }}
    />
  );
}

function ModelTable({
  models,
  selected,
  onSelect,
}: {
  models: PropModel[];
  selected: string;
  onSelect: (model: string) => void;
}) {
  const [search, setSearch] = useState('');
  const filtered = useMemo(() => {
    const q = search.toLowerCase();
    return models.filter(model => !q || model.label.toLowerCase().includes(q) || model.model.toLowerCase().includes(q));
  }, [models, search]);

  return (
    <div>
      <input
        type="text"
        placeholder="Filter props..."
        value={search}
        autoFocus
        onChange={event => setSearch(event.target.value)}
        style={{
          width: '100%',
          marginBottom: 10,
          fontSize: 13,
          background: 'var(--bg-input)',
          border: '1px solid var(--border)',
          borderRadius: 'var(--radius-sm)',
          color: 'var(--text-primary)',
          padding: '7px 10px',
          fontFamily: 'inherit',
          outline: 'none',
        }}
      />
      <div
        style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fill, minmax(96px, 1fr))',
          gap: 6,
          maxHeight: 240,
          overflowY: 'auto',
          paddingRight: 4,
        }}
      >
        {filtered.map(model => (
          <button
            key={model.model}
            type="button"
            onClick={() => onSelect(model.model)}
            title={model.model}
            style={{
              padding: '7px 5px 6px',
              border: `1px solid ${selected === model.model ? 'var(--accent)' : 'var(--border)'}`,
              borderRadius: 7,
              cursor: 'pointer',
              textAlign: 'center',
              background: selected === model.model ? 'var(--accent-dim)' : 'var(--bg-elevated)',
              transition: 'border-color 0.15s, background 0.15s',
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'center',
              gap: 4,
              color: 'inherit',
              fontFamily: 'inherit',
            }}
          >
            <PropImage model={model.model} size={44} />
            <span
              style={{
                fontSize: 10,
                color: selected === model.model ? 'var(--text-accent)' : 'var(--text-secondary)',
                fontWeight: 600,
                overflow: 'hidden',
                textOverflow: 'ellipsis',
                whiteSpace: 'nowrap',
                width: '100%',
              }}
            >
              {model.label}
            </span>
          </button>
        ))}
        {filtered.length === 0 && (
          <div style={{ gridColumn: '1/-1', textAlign: 'center', color: 'var(--text-muted)', fontSize: 12, padding: 16 }}>
            No props match "{search}".
          </div>
        )}
      </div>
    </div>
  );
}

function ConfirmDialog({ state, onClose }: { state: ConfirmState | null; onClose: () => void }) {
  if (!state) return null;

  return (
    <div
      style={{
        position: 'fixed',
        inset: 0,
        background: 'rgba(0,0,0,0.62)',
        zIndex: 9200,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
      }}
      onClick={event => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <div className="modal" style={{ display: 'block' }}>
        <div className="modal-header">
          <h3>{state.title}</h3>
        </div>
        <div className="modal-body">
          <p style={{ fontSize: 13.5, color: 'var(--text-muted)', lineHeight: 1.6, marginBottom: 20 }}>
            {state.message}
          </p>
          <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 10 }}>
            <button className="btn-outline" onClick={onClose}>Cancel</button>
            <button
              className="btn-danger"
              onClick={() => {
                const action = state.action;
                onClose();
                action();
              }}
            >
              Confirm
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

function AddPropModal({ onClose, propModels }: { onClose: () => void; propModels: PropModel[] }) {
  const [name, setName] = useState('');
  const [model, setModel] = useState(propModels[0]?.model ?? '');

  useEffect(() => {
    if (!propModels.some(item => item.model === model)) {
      setModel(propModels[0]?.model ?? '');
    }
  }, [propModels, model]);

  const handleSubmit = (event: React.FormEvent) => {
    event.preventDefault();
    const trimmedName = name.trim();
    if (!trimmedName || !model) return;
    onClose();
    setTimeout(() => {
      void sendNuiMessage('adminAddPersistentDevice', {
        mode: 'prop',
        label: trimmedName,
        propModel: model,
      });
    }, 30);
  };

  return (
    <div
      style={{
        position: 'fixed',
        inset: 0,
        background: 'rgba(0,0,0,0.6)',
        zIndex: 9000,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
      }}
      onClick={event => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <div
        style={{
          background: 'var(--bg-modal)',
          border: '1px solid var(--border)',
          borderRadius: 'var(--radius-xl)',
          boxShadow: 'var(--shadow-lg)',
          width: 580,
          maxWidth: '90vw',
          maxHeight: '80vh',
          display: 'flex',
          flexDirection: 'column',
          overflow: 'hidden',
        }}
        >
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '16px 20px', borderBottom: '1px solid var(--border)', flexShrink: 0 }}>
          <h3 style={{ fontSize: 16, fontWeight: 700 }}>Add Prop Device</h3>
          <button className="btn-icon btn-sm" onClick={onClose} aria-label="Close">x</button>
        </div>
        <form onSubmit={handleSubmit} style={{ padding: '20px', display: 'flex', flexDirection: 'column', gap: 16, overflowY: 'auto' }}>
          <div className="admin-field">
            <span>Device Name</span>
            <input type="text" value={name} onChange={event => setName(event.target.value)} placeholder="e.g. Lobby TV" autoFocus />
          </div>
          <div className="admin-field">
            <span>Prop Model {model && <span style={{ color: 'var(--accent)', fontSize: 11, marginLeft: 6 }}>{model}</span>}</span>
            {propModels.length > 0
              ? <ModelTable models={propModels} selected={model} onSelect={setModel} />
              : <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>No placeable prop models are available.</div>
            }
          </div>
          <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8, paddingTop: 4, flexShrink: 0 }}>
            <button type="button" className="btn-outline" onClick={onClose}>Cancel</button>
            <button type="submit" className="btn-accent" disabled={!name.trim() || !model}>Start Placement</button>
          </div>
        </form>
      </div>
    </div>
  );
}

function AddInteractionModal({ onClose }: { onClose: () => void }) {
  const [name, setName] = useState('');

  const handleSubmit = (event: React.FormEvent) => {
    event.preventDefault();
    const trimmedName = name.trim();
    if (!trimmedName) return;
    onClose();
    setTimeout(() => {
      void sendNuiMessage('adminAddPersistentDevice', {
        mode: 'interaction',
        label: trimmedName,
      });
    }, 30);
  };

  return (
    <div
      style={{
        position: 'fixed',
        inset: 0,
        background: 'rgba(0,0,0,0.6)',
        zIndex: 9000,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
      }}
      onClick={event => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <div
        style={{
          background: 'var(--bg-modal)',
          border: '1px solid var(--border)',
          borderRadius: 'var(--radius-xl)',
          boxShadow: 'var(--shadow-lg)',
          width: 460,
          maxWidth: '90vw',
          display: 'flex',
          flexDirection: 'column',
          overflow: 'hidden',
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '16px 20px', borderBottom: '1px solid var(--border)', flexShrink: 0 }}>
          <h3 style={{ fontSize: 16, fontWeight: 700 }}>Add Interaction Point</h3>
          <button className="btn-icon btn-sm" onClick={onClose} aria-label="Close">x</button>
        </div>
        <form onSubmit={handleSubmit} style={{ padding: '20px', display: 'flex', flexDirection: 'column', gap: 16 }}>
          <div className="admin-field">
            <span>Interaction Name</span>
            <input type="text" value={name} onChange={event => setName(event.target.value)} placeholder="e.g. Front Desk Speaker" autoFocus />
          </div>
          <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8, paddingTop: 4 }}>
            <button type="button" className="btn-outline" onClick={onClose}>Cancel</button>
            <button type="submit" className="btn-accent" disabled={!name.trim()}>Start Placement</button>
          </div>
        </form>
      </div>
    </div>
  );
}

export function AdminView() {
  const [adminData, setAdminData] = useState<any>(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedHandle, setSelectedHandle] = useState<string | null>(null);
  const [selectedDeviceSnapshot, setSelectedDeviceSnapshot] = useState<any | null>(null);
  const [showAddInteractionModal, setShowAddInteractionModal] = useState(false);
  const [showAddPropModal, setShowAddPropModal] = useState(false);
  const [viewRange, setViewRange] = useState(50);
  const [confirmState, setConfirmState] = useState<ConfirmState | null>(null);

  useEffect(() => {
    const handler = (event: any) => {
      const detail = event.detail ?? null;
      setAdminData(detail);
      if (detail?.selectedHandle != null) setSelectedHandle(String(detail.selectedHandle));
    };
    window.addEventListener('pmms:adminUpdate', handler);
    return () => window.removeEventListener('pmms:adminUpdate', handler);
  }, []);

  useEffect(() => {
    const handler = (event: any) => {
      if (Object.prototype.hasOwnProperty.call(event.detail ?? {}, 'handle')) {
        const nextHandle = event.detail?.handle;
        if (nextHandle == null) {
          setSelectedDeviceSnapshot(null);
          setSelectedHandle(null);
        } else {
          setSelectedHandle(String(nextHandle));
        }
      }
    };
    window.addEventListener('pmms:adminSelectHandle', handler);
    return () => window.removeEventListener('pmms:adminSelectHandle', handler);
  }, []);

  const adminMaxRange: number = adminData?.adminMaxRange ?? 200;

  useEffect(() => {
    setViewRange(current => Math.min(current, adminMaxRange));
  }, [adminMaxRange]);

  useEffect(() => {
    void sendNuiMessage('setAdminDiscoveryRange', { range: viewRange });
  }, [viewRange]);

  const unifiedDevices = useMemo(() => {
    if (!adminData) return [];
    const map = new Map<string, any>();
    (adminData.adminState?.devices ?? []).forEach((device: any) => map.set(String(device.handle), { ...device, isKnown: true }));
    (adminData.usableMediaPlayers ?? []).forEach((device: any) => {
      const key = String(device.handle);
      if (map.has(key)) {
        const existing = map.get(key);
        existing.isNearby = true;
        existing.distance = device.distance;
        existing.coords = existing.coords ?? device.coords;
      } else {
        map.set(key, { ...device, isNearby: true });
      }
    });
    return Array.from(map.values());
  }, [adminData]);

  const filteredDevices = useMemo(() => {
    const q = searchQuery.toLowerCase();
    return unifiedDevices.filter(device => {
      const distance = device.distance ?? -1;
      if (distance >= 0 && distance > viewRange) return false;
      if (!q) return true;
      return String(device.label ?? '').toLowerCase().includes(q) || String(device.handle ?? '').toLowerCase().includes(q);
    });
  }, [unifiedDevices, searchQuery, viewRange]);

  const liveSelectedDevice = useMemo(
    () => selectedHandle ? unifiedDevices.find(device => String(device.handle) === selectedHandle) ?? null : null,
    [unifiedDevices, selectedHandle]
  );

  useEffect(() => {
    if (liveSelectedDevice) {
      setSelectedDeviceSnapshot(liveSelectedDevice);
    } else if (!selectedHandle) {
      setSelectedDeviceSnapshot(null);
    }
  }, [liveSelectedDevice, selectedHandle]);

  const selectedDevice = liveSelectedDevice
    ?? (selectedHandle && selectedDeviceSnapshot && String(selectedDeviceSnapshot.handle) === selectedHandle
      ? selectedDeviceSnapshot
      : null);

  const propModels: PropModel[] = adminData?.propModels ?? [];
  const speakerModels: PropModel[] = adminData?.speakerModels?.length ? adminData.speakerModels : propModels;
  const profiles: any[] = adminData?.deviceProfiles ?? adminData?.adminState?.profiles ?? [];
  const jobs: JobOption[] = adminData?.adminState?.jobs ?? adminData?.jobs ?? [];

  const askConfirm = (title: string, message: string, action: () => void) => setConfirmState({ title, message, action });

  return (
    <div id="view-admin" className="view staff-only">
      <div className="view-header">
        <h2>Admin Panel</h2>
        <div className="view-header-actions">
          <button className="btn-outline" onClick={() => setShowAddInteractionModal(true)}>
            Add Interaction Point
          </button>
          <button className="btn-accent" onClick={() => setShowAddPropModal(true)}>Add Prop Device</button>
        </div>
      </div>
      <div style={{ marginBottom: 14, display: 'flex', alignItems: 'center', gap: 12 }}>
        <span style={{ fontSize: 12, color: 'var(--text-muted)', whiteSpace: 'nowrap' }}>
          View Range: <strong style={{ color: 'var(--text-primary)' }}>{viewRange} m</strong>
        </span>
        <input
          type="range"
          min={10}
          max={adminMaxRange}
          step={5}
          value={viewRange}
          onChange={event => setViewRange(Number(event.target.value))}
          style={{ flex: 1, accentColor: 'var(--accent)' }}
        />
        <span style={{ fontSize: 11, color: 'var(--text-muted)' }}>max {adminMaxRange}m</span>
      </div>
      <div className="admin-panel-layout">
        <section className="admin-panel-card">
          <div className="section-row" style={{ marginBottom: 10 }}>
            <span className="section-title">Devices</span>
            <span className="section-count">{filteredDevices.length}</span>
          </div>
          <div style={{ position: 'relative', marginBottom: 10 }}>
            <input
              type="text"
              placeholder="Search..."
              value={searchQuery}
              onChange={event => setSearchQuery(event.target.value)}
              style={{ width: '100%', fontSize: 13, background: 'var(--bg-input)', border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', color: 'var(--text-primary)', padding: '6px 10px', fontFamily: 'inherit', outline: 'none' }}
            />
          </div>
          <div className="admin-device-list">
            {filteredDevices.map((device: any) => {
              const handle = String(device.handle);
              const isActive = selectedHandle === handle;
              return (
                <div key={handle} className={`admin-device-row ${isActive ? 'active' : ''}`} onClick={() => setSelectedHandle(handle)}>
                  <div className="admin-device-row-title">{device.label || 'Unknown Device'}</div>
                  <div className="admin-device-row-meta">#{device.handle}{device.distance != null ? ` - ${Math.round(device.distance)}m` : ''}</div>
                  {device.active && <div className="admin-device-row-badge">LIVE</div>}
                </div>
              );
            })}
            {filteredDevices.length === 0 && <div className="admin-device-detail-empty">No devices in range.</div>}
          </div>
        </section>
        <section className="admin-panel-card admin-panel-detail">
          {!selectedDevice
            ? <div className="admin-device-detail-empty">Select a device to manage it.</div>
            : (
              <DeviceDetailPane
                device={selectedDevice}
                profiles={profiles}
                speakerModels={speakerModels}
                jobs={jobs}
                askConfirm={askConfirm}
              />
            )
          }
        </section>
      </div>
      {showAddInteractionModal && <AddInteractionModal onClose={() => setShowAddInteractionModal(false)} />}
      {showAddPropModal && <AddPropModal onClose={() => setShowAddPropModal(false)} propModels={propModels} />}
      <ConfirmDialog state={confirmState} onClose={() => setConfirmState(null)} />
    </div>
  );
}

function DeviceDetailPane({
  device,
  profiles,
  speakerModels,
  jobs,
  askConfirm,
}: {
  device: any;
  profiles: any[];
  speakerModels: PropModel[];
  jobs: JobOption[];
  askConfirm: (title: string, message: string, action: () => void) => void;
}) {
  const settings = device.settings ?? {};
  const currentLock = device.adminLock ?? settings.adminLock ?? { mode: 'public' };
  const savedConfiguredMode = device.configuredRequestMode ?? settings.requestMode ?? device.requestMode ?? 'queue';
  const effectiveRequestMode = device.effectiveRequestMode ?? device.requestMode ?? savedConfiguredMode;
  const requestModeReason = device.requestModeReason ?? '';
  const [label, setLabel] = useState(device.label ?? '');
  const [showSpeakerPicker, setShowSpeakerPicker] = useState(false);
  const [speakerModel, setSpeakerModel] = useState(speakerModels[0]?.model ?? '');
  const [requestMode, setRequestMode] = useState(savedConfiguredMode);
  const [lockMode, setLockMode] = useState(currentLock.mode ?? 'public');
  const [requiredJob, setRequiredJob] = useState(currentLock.job ?? '');

  useEffect(() => {
    setLabel(device.label ?? '');
    setRequestMode(savedConfiguredMode);
    setLockMode(currentLock.mode ?? 'public');
    setRequiredJob(currentLock.job ?? '');
  }, [device.handle, device.label, savedConfiguredMode, currentLock.mode, currentLock.job]);

  useEffect(() => {
    if (!speakerModels.some(item => item.model === speakerModel)) {
      setSpeakerModel(speakerModels[0]?.model ?? '');
    }
  }, [speakerModels, speakerModel]);

  const speakers: any[] = device.linkedSpeakers ?? settings.linkedSpeakers ?? [];
  const handle = device.handle;
  const savedLockMode = currentLock.mode ?? 'public';
  const savedJob = currentLock.job ?? '';
  const pendingRequests: any[] = device.pendingRequests ?? [];
  const settingsDirty = requestMode !== savedConfiguredMode || lockMode !== savedLockMode || requiredJob !== savedJob;
  const canSaveAccess = lockMode !== 'job' || requiredJob.trim().length > 0;

  const saveAccessSettings = () => {
    if (!canSaveAccess) return;
    void sendNuiMessage('adminSetRequestMode', { handle, mode: requestMode });
    void sendNuiMessage('adminSetLock', {
      handle,
      lock: {
        ...currentLock,
        mode: lockMode,
        job: lockMode === 'job' ? requiredJob.trim() : undefined,
      },
    });
  };

  return (
    <div className="admin-detail-content">
      <div className="admin-detail-header">
        <div style={{ flex: 1 }}>
          <input
            type="text"
            value={label}
            onChange={event => setLabel(event.target.value)}
            onBlur={() => {
              const trimmed = label.trim();
              if (trimmed && trimmed !== device.label) void sendNuiMessage('adminRenameDevice', { handle, name: trimmed });
            }}
            style={{ fontSize: 17, fontWeight: 700, background: 'transparent', border: '1px solid transparent', padding: '2px 6px', marginLeft: -6, color: 'var(--text-primary)', borderRadius: 4, width: '100%', fontFamily: 'inherit' }}
          />
          <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 2 }}>Handle: {handle}</div>
        </div>
        <div className="admin-detail-actions">
          <button className="btn-outline btn-sm" onClick={() => void sendNuiMessage('adminResetProfile', { handle })}>Reset</button>
          {device.persistent && (
            <button
              className="btn-danger btn-sm"
              onClick={() => askConfirm('Remove persistent device?', 'This deletes the saved prop or interaction point from persistent storage.', () => void sendNuiMessage('adminRemovePersistentDevice', { handle }))}
            >
              Delete
            </button>
          )}
        </div>
      </div>
      <div className="admin-detail-section" style={{ borderTop: 'none', paddingTop: 0 }}>
        <div className="section-row">
          <span className="section-title">Access</span>
          <button className="btn-accent btn-sm" disabled={!settingsDirty || !canSaveAccess} onClick={saveAccessSettings}>Save</button>
        </div>
        <div className="admin-hint" style={{ marginBottom: 10 }}>
          Configured: <strong style={{ color: 'var(--text-primary)' }}>{savedConfiguredMode}</strong> | Live behavior: <strong style={{ color: 'var(--text-primary)' }}>{effectiveRequestMode}</strong>
        </div>
        {requestModeReason && <div className="admin-hint" style={{ marginBottom: 12 }}>{requestModeReason}</div>}
        <div className="admin-grid-two">
          <div className="admin-field">
            <span>Request Mode</span>
            <select value={requestMode} onChange={event => setRequestMode(event.target.value)}>
              <option value="queue">Queue</option>
              <option value="pending">Pending Approval</option>
              <option value="disabled">Disabled</option>
            </select>
          </div>
          <div className="admin-field">
            <span>Access Lock</span>
            <select value={lockMode} onChange={event => setLockMode(event.target.value)}>
              <option value="public">Public</option>
              <option value="job">Specific Job</option>
              <option value="admin">Admin Only</option>
            </select>
          </div>
          {lockMode === 'job' && (
            <>
              <div className="admin-field">
                <span>Existing Job</span>
                <select value="" onChange={event => setRequiredJob(event.target.value)}>
                  <option value="">Select existing job</option>
                  {jobs.map(job => (
                    <option key={job.name} value={job.name}>{job.label || job.name} ({job.name})</option>
                  ))}
                </select>
              </div>
              <div className="admin-field">
                <span>Required Job</span>
                <input type="text" placeholder="e.g. police" value={requiredJob} onChange={event => setRequiredJob(event.target.value)} />
              </div>
            </>
          )}
        </div>
      </div>
      <div className="admin-detail-section">
        <div className="section-row">
          <span className="section-title">Pending Requests</span>
          {pendingRequests.length > 0 && (
            <button
              className="btn-outline btn-sm"
              onClick={() => askConfirm('Clear pending requests?', 'This removes every pending request on this device.', () => void sendNuiMessage('adminClearRequests', { handle }))}
            >
              Clear All
            </button>
          )}
        </div>
        {pendingRequests.length > 0 ? (
          <div className="admin-log-list">
            {pendingRequests.map((request: any) => (
              <div key={request.id} className="admin-pending-row">
                <div className="admin-pending-main">
                  <strong>{request.title || 'Request'}</strong>
                  <span>{request.requesterName || request.playerName || 'Unknown player'}</span>
                  {request.url && <small>{request.url}</small>}
                </div>
                <div className="admin-pending-actions">
                  <button className="btn-outline btn-sm btn-xs" onClick={() => void sendNuiMessage('adminApproveRequest', { handle, requestId: request.id, playNext: true })}>Play Next</button>
                  <button className="btn-outline btn-sm btn-xs" onClick={() => void sendNuiMessage('adminApproveRequest', { handle, requestId: request.id, playNext: false })}>Queue</button>
                  <button className="btn-danger btn-sm btn-xs" onClick={() => void sendNuiMessage('adminRejectRequest', { handle, requestId: request.id })}>Reject</button>
                </div>
              </div>
            ))}
          </div>
        ) : (
          <div className="admin-empty-small">No pending requests.</div>
        )}
      </div>
      {profiles.length > 0 && (
        <div className="admin-detail-section">
          <div className="section-row"><span className="section-title">Profile</span></div>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
            {[{ key: '', label: 'Custom' }, ...profiles].map(profile => (
              <button
                key={profile.key}
                className="pill-btn"
                style={settings.profile === profile.key ? { borderColor: 'var(--accent)', color: 'var(--text-accent)', background: 'var(--accent-dim)' } : {}}
                onClick={() => void sendNuiMessage('adminApplyProfile', { handle, profile: profile.key })}
              >
                {profile.label}
              </button>
            ))}
          </div>
        </div>
      )}
      <div className="admin-detail-section">
        <div className="section-row"><span className="section-title">Linked Speakers</span></div>
        <div className="admin-speaker-list">
          {speakers.map((speaker: any, index: number) => (
            <div key={speaker.id ?? index} className="admin-speaker-row">
              <div className="admin-speaker-info">
                <span className="admin-speaker-name">{speaker.propModel ?? 'Speaker'}</span>
                <span className="admin-speaker-meta">{speaker.persistent ? 'Persistent' : 'Session'}{speaker.createdByName ? ` - ${speaker.createdByName}` : ''}</span>
              </div>
              <button
                className="btn-danger btn-sm btn-xs"
                onClick={() => askConfirm('Remove speaker?', 'This removes the selected linked speaker from this device.', () => void sendNuiMessage('removeLinkedSpeaker', { handle, speakerId: speaker.id }))}
              >
                x
              </button>
            </div>
          ))}
          {speakers.length === 0 && <div className="admin-speaker-empty">No linked speakers.</div>}
        </div>
        {showSpeakerPicker && (
          <div style={{ marginTop: 10, padding: 12, border: '1px solid var(--border)', borderRadius: 8, background: 'var(--bg-elevated)' }}>
            <div style={{ fontSize: 12, fontWeight: 600, marginBottom: 8 }}>Choose Speaker Model</div>
            <ModelTable models={speakerModels} selected={speakerModel} onSelect={setSpeakerModel} />
            <div style={{ display: 'flex', gap: 8, marginTop: 10, flexWrap: 'wrap' }}>
              <button
                className="btn-outline btn-sm"
                disabled={!speakerModel}
                onClick={() => {
                  void sendNuiMessage('adminAddPersistentSpeaker', { handle, propModel: speakerModel });
                  setShowSpeakerPicker(false);
                }}
              >
                Place Persistent
              </button>
              <button className="btn-outline btn-sm" onClick={() => setShowSpeakerPicker(false)}>Cancel</button>
            </div>
          </div>
        )}
        <div style={{ display: 'flex', gap: 8, marginTop: 10, flexWrap: 'wrap' }}>
          {!showSpeakerPicker && <button className="pill-btn" onClick={() => setShowSpeakerPicker(true)}>+ Add Speaker</button>}
          {speakers.length > 0 && (
            <button
              className="pill-btn pill-btn-danger"
              onClick={() => askConfirm('Clear all speakers?', 'This removes every linked speaker from this device.', () => void sendNuiMessage('adminClearLinkedSpeakers', { handle }))}
            >
              Clear All
            </button>
          )}
        </div>
      </div>
      <div className="admin-detail-section">
        <div className="section-row"><span className="section-title">Live Actions</span></div>
        <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
          <button className="pill-btn" onClick={() => void sendNuiMessage('adminClearSessionLock', { handle })}>Clear Lock</button>
          <button
            className="pill-btn pill-btn-danger"
            onClick={() => askConfirm('Force reset this device?', 'This clears the live runtime state for this device.', () => void sendNuiMessage('forceResetDevice', { handle }))}
          >
            Force Reset
          </button>
        </div>
      </div>
    </div>
  );
}
