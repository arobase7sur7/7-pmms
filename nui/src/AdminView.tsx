import React, { useEffect, useState, useMemo, useRef } from 'react';
import { sendNuiMessage } from './nuiBridge';

// ── Types ─────────────────────────────────────────────────────────────────────
interface PropModel { model: string; label: string; isTv?: boolean; }

// ── Image with extension fallback ─────────────────────────────────────────────
function PropImage({ model, size = 48 }: { model: string; size?: number }) {
  const [idx, setIdx] = useState(0);
  const [failed, setFailed] = useState(false);
  const exts = ['png', 'jpg', 'webp'];
  const src = failed
    ? 'ui/assets/props/fallback.png'
    : `ui/assets/props/${model}.${exts[idx]}`;

  return (
    <img
      src={src}
      alt={model}
      onError={() => {
        if (!failed && idx < exts.length - 1) setIdx(i => i + 1);
        else setFailed(true);
      }}
      style={{ width: size, height: size, objectFit: 'contain', borderRadius: 4, background: 'rgba(255,255,255,0.04)', flexShrink: 0 }}
    />
  );
}

// ── Model grid table (for prop device picker) ─────────────────────────────────
function ModelTable({
  models,
  selected,
  onSelect,
}: {
  models: PropModel[];
  selected: string;
  onSelect: (m: string) => void;
}) {
  const [search, setSearch] = useState('');
  const filtered = useMemo(() => {
    const q = search.toLowerCase();
    return models.filter(m => !q || m.label.toLowerCase().includes(q) || m.model.toLowerCase().includes(q));
  }, [models, search]);

  return (
    <div>
      <input
        type="text"
        placeholder="Filter props…"
        value={search}
        autoFocus
        onChange={e => setSearch(e.target.value)}
        style={{
          width: '100%', marginBottom: 10, fontSize: 13,
          background: 'var(--bg-input)', border: '1px solid var(--border)',
          borderRadius: 'var(--radius-sm)', color: 'var(--text-primary)',
          padding: '7px 10px', fontFamily: 'inherit', outline: 'none',
        }}
      />
      <div style={{
        display: 'grid',
        gridTemplateColumns: 'repeat(auto-fill, minmax(96px, 1fr))',
        gap: 6,
        maxHeight: 240,
        overflowY: 'auto',
        paddingRight: 4,
      }}>
        {filtered.map(m => (
          <div
            key={m.model}
            onClick={() => onSelect(m.model)}
            title={m.model}
            style={{
              padding: '7px 5px 6px',
              border: `1px solid ${selected === m.model ? 'var(--accent)' : 'var(--border)'}`,
              borderRadius: 7,
              cursor: 'pointer',
              textAlign: 'center',
              background: selected === m.model ? 'var(--accent-dim)' : 'var(--bg-elevated)',
              transition: 'border-color 0.15s, background 0.15s',
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'center',
              gap: 4,
            }}
          >
            <PropImage model={m.model} size={44} />
            <div style={{
              fontSize: 10, color: selected === m.model ? 'var(--text-accent)' : 'var(--text-secondary)',
              fontWeight: 600, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
              width: '100%',
            }}>
              {m.label}
            </div>
          </div>
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


// ── Add Prop Modal ───────────────────────────────────────────────────────────
function AddPropModal({ onClose, propModels }: { onClose: () => void; propModels: PropModel[] }) {
  const [name, setName] = useState('');
  const [model, setModel] = useState(propModels[0]?.model ?? '');

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    const trimmedName = name.trim();
    if (!trimmedName || !model) return;
    // Close first so HideUi() doesn't freeze modal in memory
    onClose();
    // Short defer so React can teardown the modal before NUI focus is released
    setTimeout(() => {
      sendNuiMessage('adminAddPersistentDevice', {
        mode: 'prop',
        label: trimmedName,
        propModel: model,
      });
    }, 30);
  };

  return (
    <div
      style={{
        position: 'fixed', inset: 0,
        background: 'rgba(0,0,0,0.6)',
        zIndex: 9000,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}
      onClick={e => { if (e.target === e.currentTarget) onClose(); }}
    >
      <div style={{
        background: 'var(--bg-modal)',
        border: '1px solid var(--border)',
        borderRadius: 'var(--radius-xl)',
        boxShadow: 'var(--shadow-lg)',
        width: 580, maxWidth: '90vw',
        maxHeight: '80vh',
        display: 'flex', flexDirection: 'column',
        overflow: 'hidden',
      }}>
        <div style={{
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          padding: '16px 20px', borderBottom: '1px solid var(--border)',
          flexShrink: 0,
        }}>
          <h3 style={{ fontSize: 16, fontWeight: 700 }}>Add Prop Device</h3>
          <button onClick={onClose} style={{ background: 'none', border: 'none', color: 'var(--text-muted)', cursor: 'pointer', fontSize: 18, lineHeight: 1 }}>✕</button>
        </div>

        <form onSubmit={handleSubmit} style={{ padding: '20px', display: 'flex', flexDirection: 'column', gap: 16, overflowY: 'auto' }}>
          <div className="admin-field">
            <span>Device Name</span>
            <input
              type="text"
              value={name}
              onChange={e => setName(e.target.value)}
              placeholder="e.g. Lobby TV"
              autoFocus
            />
          </div>

          <div className="admin-field">
            <span>Prop Model {model && <span style={{ color: 'var(--accent)', fontSize: 11, marginLeft: 6 }}>{model}</span>}</span>
            {propModels.length > 0
              ? <ModelTable models={propModels} selected={model} onSelect={setModel} />
              : <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>No prop models configured in Config.models.</div>
            }
          </div>

          <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8, paddingTop: 4, flexShrink: 0 }}>
            <button type="button" className="btn-outline" onClick={onClose}>Cancel</button>
            <button type="submit" className="btn-accent" disabled={!name.trim() || !model}>
              Start Placement
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

// ── Main AdminView ────────────────────────────────────────────────────────────
export function AdminView() {
  const [adminData, setAdminData] = useState<any>(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedHandle, setSelectedHandle] = useState<string | null>(null);
  const [showAddPropModal, setShowAddPropModal] = useState(false);
  const [viewRange, setViewRange] = useState(200);

  useEffect(() => {
    const handler = (e: any) => setAdminData(e.detail ?? null);
    window.addEventListener('pmms:adminUpdate', handler);
    return () => window.removeEventListener('pmms:adminUpdate', handler);
  }, []);

  useEffect(() => {
    const handler = (e: any) => {
      if (e.detail?.handle != null) setSelectedHandle(String(e.detail.handle));
    };
    window.addEventListener('pmms:adminSelectHandle', handler);
    return () => window.removeEventListener('pmms:adminSelectHandle', handler);
  }, []);

  // Sync viewRange max from adminData
  const adminMaxRange: number = adminData?.adminMaxRange ?? 200;
  useEffect(() => { setViewRange(adminMaxRange); }, [adminMaxRange]);

  const unifiedDevices = useMemo(() => {
    if (!adminData) return [];
    const map = new Map<string, any>();
    (adminData.adminState?.devices ?? []).forEach((d: any) => map.set(String(d.handle), { ...d, isKnown: true }));
    (adminData.usableMediaPlayers ?? []).forEach((d: any) => {
      const k = String(d.handle);
      if (map.has(k)) { const ex = map.get(k); ex.isNearby = true; ex.distance = d.distance; }
      else map.set(k, { ...d, isNearby: true });
    });
    return Array.from(map.values());
  }, [adminData]);

  const filteredDevices = useMemo(() => {
    const q = searchQuery.toLowerCase();
    return unifiedDevices.filter(d => {
      const dist = d.distance ?? -1;
      if (dist >= 0 && dist > viewRange) return false;
      if (!q) return true;
      return String(d.label ?? '').toLowerCase().includes(q) || String(d.handle ?? '').toLowerCase().includes(q);
    });
  }, [unifiedDevices, searchQuery, viewRange]);

  const selectedDevice = useMemo(
    () => selectedHandle ? unifiedDevices.find(d => String(d.handle) === selectedHandle) ?? null : null,
    [unifiedDevices, selectedHandle]
  );

  const propModels: PropModel[] = adminData?.propModels ?? [];
  const speakerModels: PropModel[] = adminData?.speakerModels?.length ? adminData.speakerModels : propModels;
  const profiles: any[] = adminData?.deviceProfiles ?? [];

  return (
    <div id="view-admin" className="view staff-only">
      <div className="view-header">
        <h2>Admin Panel</h2>
        <div className="view-header-actions">
          <button className="btn-outline" onClick={() => { sendNuiMessage('adminAddPersistentDevice', { mode: 'interaction' }); }}>
            Add Interaction Point
          </button>
          <button className="btn-accent" onClick={() => setShowAddPropModal(true)}>Add Prop Device</button>
        </div>
      </div>

      {/* View range */}
      <div style={{ marginBottom: 14, display: 'flex', alignItems: 'center', gap: 12 }}>
        <span style={{ fontSize: 12, color: 'var(--text-muted)', whiteSpace: 'nowrap' }}>
          View Range: <strong style={{ color: 'var(--text-primary)' }}>{viewRange} m</strong>
        </span>
        <input
          type="range" min={10} max={adminMaxRange} step={5} value={viewRange}
          onChange={e => setViewRange(Number(e.target.value))}
          style={{ flex: 1, accentColor: 'var(--accent)' }}
        />
        <span style={{ fontSize: 11, color: 'var(--text-muted)' }}>max {adminMaxRange}m</span>
      </div>

      <div className="admin-panel-layout">
        {/* Device list */}
        <section className="admin-panel-card">
          <div className="section-row" style={{ marginBottom: 10 }}>
            <span className="section-title">Devices</span>
            <span className="section-count">{filteredDevices.length}</span>
          </div>
          <div style={{ position: 'relative', marginBottom: 10 }}>
            <input
              type="text" placeholder="Search…"
              value={searchQuery} onChange={e => setSearchQuery(e.target.value)}
              style={{ width: '100%', fontSize: 13, background: 'var(--bg-input)', border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', color: 'var(--text-primary)', padding: '6px 10px', fontFamily: 'inherit', outline: 'none' }}
            />
          </div>
          <div className="admin-device-list">
            {filteredDevices.map((d: any) => {
              const hs = String(d.handle);
              const isActive = selectedHandle === hs;
              return (
                <div key={hs} className={`admin-device-row ${isActive ? 'active' : ''}`} onClick={() => setSelectedHandle(hs)}>
                  <div className="admin-device-row-title">{d.label || 'Unknown Device'}</div>
                  <div className="admin-device-row-meta">
                    #{d.handle}{d.isNearby ? ` · ${Math.round(d.distance ?? 0)}m` : ''}
                  </div>
                  {d.active && <div className="admin-device-row-badge">LIVE</div>}
                </div>
              );
            })}
            {filteredDevices.length === 0 && (
              <div className="admin-device-detail-empty">No devices in range.</div>
            )}
          </div>
        </section>

        {/* Detail pane */}
        <section className="admin-panel-card admin-panel-detail">
          {!selectedDevice
            ? <div className="admin-device-detail-empty">Select a device to manage it.</div>
            : <DeviceDetailPane device={selectedDevice} profiles={profiles} speakerModels={speakerModels} />
          }
        </section>
      </div>

      {showAddPropModal && (
        <AddPropModal onClose={() => setShowAddPropModal(false)} propModels={propModels} />
      )}
    </div>
  );
}

// ── Device detail pane ────────────────────────────────────────────────────────
function DeviceDetailPane({ device, profiles, speakerModels }: { device: any; profiles: any[]; speakerModels: PropModel[] }) {
  const [label, setLabel] = useState(device.label ?? '');
  const [showSpeakerPicker, setShowSpeakerPicker] = useState(false);
  const [speakerModel, setSpeakerModel] = useState(speakerModels[0]?.model ?? '');

  useEffect(() => { setLabel(device.label ?? ''); }, [device.handle]);

  const speakers: any[] = device.linkedSpeakers ?? device.settings?.linkedSpeakers ?? [];
  const settings = device.settings ?? {};
  const handle = device.handle;

  return (
    <div className="admin-detail-content">
      {/* Header */}
      <div className="admin-detail-header">
        <div style={{ flex: 1 }}>
          <input
            type="text" value={label}
            onChange={e => setLabel(e.target.value)}
            onBlur={() => { if (label !== device.label) sendNuiMessage('adminRenameDevice', { handle, name: label }); }}
            style={{ fontSize: 17, fontWeight: 700, background: 'transparent', border: '1px solid transparent', padding: '2px 6px', marginLeft: -6, color: 'var(--text-primary)', borderRadius: 4, width: '100%', fontFamily: 'inherit' }}
          />
          <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 2 }}>Handle: {handle}</div>
        </div>
        <div className="admin-detail-actions">
          <button className="btn-outline btn-sm" onClick={() => sendNuiMessage('adminResetProfile', { handle })}>Reset</button>
          <button className="btn-danger btn-sm" onClick={() => { if (confirm('Remove this device permanently?')) sendNuiMessage('adminRemovePersistentDevice', { handle }); }}>Delete</button>
        </div>
      </div>

      {/* Settings */}
      <div className="admin-detail-section" style={{ borderTop: 'none', paddingTop: 0 }}>
        <div className="section-row"><span className="section-title">Settings</span></div>
        <div className="admin-grid-two">
          <div className="admin-field">
            <span>Request Mode</span>
            <select value={settings.requestMode ?? 'none'} onChange={e => sendNuiMessage('adminSetRequestMode', { handle, mode: e.target.value })}>
              <option value="none">Admin Only</option>
              <option value="queue">Queue</option>
              <option value="pending">Pending Approval</option>
            </select>
          </div>
          <div className="admin-field">
            <span>Access Lock</span>
            <select value={settings.adminLock?.mode ?? 'public'} onChange={e => sendNuiMessage('adminSetDeviceSettings', { handle, settings: { ...settings, adminLock: { ...(settings.adminLock || {}), mode: e.target.value } } })}>
              <option value="public">Public</option>
              <option value="job">Specific Job</option>
            </select>
          </div>
          {settings.adminLock?.mode === 'job' && (
            <div className="admin-field">
              <span>Required Job</span>
              <input
                type="text"
                placeholder="e.g. police"
                value={settings.adminLock?.job ?? ''}
                onChange={e => sendNuiMessage('adminSetDeviceSettings', { handle, settings: { ...settings, adminLock: { ...(settings.adminLock || {}), job: e.target.value } } })}
              />
            </div>
          )}
        </div>
      </div>

      {/* Profile */}
      {profiles.length > 0 && (
        <div className="admin-detail-section">
          <div className="section-row"><span className="section-title">Profile</span></div>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
            {[{ key: '', label: 'Custom' }, ...profiles].map(p => (
              <button
                key={p.key}
                className="pill-btn"
                style={settings.profile === p.key ? { borderColor: 'var(--accent)', color: 'var(--text-accent)', background: 'var(--accent-dim)' } : {}}
                onClick={() => sendNuiMessage('adminApplyProfile', { handle, profile: p.key })}
              >
                {p.label}
              </button>
            ))}
          </div>
        </div>
      )}

      {/* Speakers */}
      <div className="admin-detail-section">
        <div className="section-row"><span className="section-title">Linked Speakers</span></div>
        <div className="admin-speaker-list">
          {speakers.map((spk: any, i: number) => (
            <div key={spk.id ?? i} className="admin-speaker-row">
              <div className="admin-speaker-info">
                <span className="admin-speaker-name">{spk.propModel ?? 'Speaker'}</span>
                <span className="admin-speaker-meta">{spk.persistent ? 'Persistent' : 'Session'}{spk.createdByName ? ` · ${spk.createdByName}` : ''}</span>
              </div>
              <button className="btn-danger btn-sm btn-xs" onClick={() => { if (confirm('Remove speaker?')) sendNuiMessage('removeLinkedSpeaker', { handle, speakerId: spk.id }); }}>✕</button>
            </div>
          ))}
          {speakers.length === 0 && <div className="admin-speaker-empty">No linked speakers.</div>}
        </div>

        {/* Speaker picker */}
        {showSpeakerPicker && (
          <div style={{ marginTop: 10, padding: 12, border: '1px solid var(--border)', borderRadius: 8, background: 'var(--bg-elevated)' }}>
            <div style={{ fontSize: 12, fontWeight: 600, marginBottom: 8 }}>Choose Speaker Model</div>
            <ModelTable models={speakerModels} selected={speakerModel} onSelect={setSpeakerModel} />
            <div style={{ display: 'flex', gap: 8, marginTop: 10, flexWrap: 'wrap' }}>
              <button className="btn-accent btn-sm" onClick={() => { sendNuiMessage('adminAddSpeaker', { handle, propModel: speakerModel }); setShowSpeakerPicker(false); }}>Place Here</button>
              <button className="btn-outline btn-sm" onClick={() => { sendNuiMessage('adminAddPersistentSpeaker', { handle, propModel: speakerModel }); setShowSpeakerPicker(false); }}>Place Persistent</button>
              <button className="btn-outline btn-sm" onClick={() => setShowSpeakerPicker(false)}>Cancel</button>
            </div>
          </div>
        )}

        <div style={{ display: 'flex', gap: 8, marginTop: 10, flexWrap: 'wrap' }}>
          {!showSpeakerPicker && <button className="pill-btn" onClick={() => setShowSpeakerPicker(true)}>+ Add Speaker</button>}
          {speakers.length > 0 && <button className="pill-btn pill-btn-danger" onClick={() => { if (confirm('Clear all speakers?')) sendNuiMessage('adminClearLinkedSpeakers', { handle }); }}>Clear All</button>}
        </div>
      </div>

      {/* Live actions */}
      <div className="admin-detail-section">
        <div className="section-row"><span className="section-title">Live Actions</span></div>
        <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
          <button className="pill-btn" onClick={() => sendNuiMessage('adminClearSessionLock', { handle })}>Clear Lock</button>
          <button className="pill-btn pill-btn-danger" onClick={() => { if (confirm('Force reset this device?')) sendNuiMessage('forceResetDevice', { handle }); }}>Force Reset</button>
        </div>
      </div>
    </div>
  );
}
