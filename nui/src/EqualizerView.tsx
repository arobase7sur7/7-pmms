import React, { useEffect, useMemo, useRef, useState } from 'react';
import { sendNuiMessage } from './nuiBridge';

interface EqPreset {
  id: string;
  label: string;
  bands: number[];
  preampDb?: number;
  highpassEnabled?: boolean;
  compressorEnabled?: boolean;
}

interface EqProfile {
  enabled: boolean;
  preampDb: number;
  highpassEnabled: boolean;
  compressorEnabled: boolean;
  bands: number[];
  customPresets: EqPreset[];
}

interface EqConfig {
  enabled: boolean;
  maxCustomPresets: number;
  bands: number[];
  bandMinDb: number;
  bandMaxDb: number;
  preampMinDb: number;
  preampMaxDb: number;
  presets: EqPreset[];
}

const FALLBACK_BANDS = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];

function makeFlatProfile(count: number): EqProfile {
  return {
    enabled: false,
    preampDb: 0,
    highpassEnabled: false,
    compressorEnabled: false,
    bands: Array(count).fill(0),
    customPresets: [],
  };
}

function clamp(value: number, min: number, max: number) {
  return Math.max(min, Math.min(max, value));
}

function formatFreq(hz: number): string {
  return hz >= 1000 ? `${hz / 1000}k` : `${hz}`;
}

function normalizeProfile(raw: any, cfg: EqConfig): EqProfile {
  const count = cfg.bands.length;
  const base = makeFlatProfile(count);
  const bands = Array.isArray(raw?.bands) ? raw.bands.slice(0, count).map((value: any) => clamp(Number(value) || 0, cfg.bandMinDb, cfg.bandMaxDb)) : base.bands;
  while (bands.length < count) bands.push(0);
  const customPresets = Array.isArray(raw?.customPresets)
    ? raw.customPresets.slice(0, cfg.maxCustomPresets).map((preset: any, index: number) => ({
      id: String(preset?.id || `custom_${index}`),
      label: String(preset?.label || `Custom ${index + 1}`).slice(0, 40),
      preampDb: clamp(Number(preset?.preampDb) || 0, cfg.preampMinDb, cfg.preampMaxDb),
      highpassEnabled: preset?.highpassEnabled === true,
      compressorEnabled: preset?.compressorEnabled === true,
      bands: normalizePresetBands(preset?.bands, cfg),
    }))
    : [];

  return {
    enabled: raw?.enabled === true,
    preampDb: clamp(Number(raw?.preampDb) || 0, cfg.preampMinDb, cfg.preampMaxDb),
    highpassEnabled: raw?.highpassEnabled === true,
    compressorEnabled: raw?.compressorEnabled === true,
    bands,
    customPresets,
  };
}

function normalizePresetBands(rawBands: any, cfg: EqConfig) {
  const bands = Array.isArray(rawBands) ? rawBands.slice(0, cfg.bands.length).map((value: any) => clamp(Number(value) || 0, cfg.bandMinDb, cfg.bandMaxDb)) : [];
  while (bands.length < cfg.bands.length) bands.push(0);
  return bands;
}

function BandSlider({
  freq,
  value,
  min,
  max,
  onChange,
}: {
  freq: number;
  value: number;
  min: number;
  max: number;
  onChange: (value: number) => void;
}) {
  const rounded = Math.round(value * 2) / 2;
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6, flex: '1 1 0', minWidth: 0 }}>
      <span style={{ fontSize: 10, color: value === 0 ? 'var(--text-muted)' : value > 0 ? 'var(--accent)' : 'var(--red)', fontWeight: 700, minHeight: 14 }}>
        {value === 0 ? '0' : value > 0 ? `+${rounded}` : `${rounded}`}
      </span>
      <div style={{ height: 120, width: 22, display: 'flex', justifyContent: 'center', alignItems: 'center' }}>
        <input
          type="range"
          min={min}
          max={max}
          step={0.5}
          value={value}
          onChange={event => onChange(parseFloat(event.target.value))}
          style={{ transform: 'rotate(-90deg)', width: 110, height: 4, cursor: 'pointer', accentColor: 'var(--accent)', background: 'rgba(255,255,255,0.1)', borderRadius: 2 }}
        />
      </div>
      <span style={{ fontSize: 9, color: 'var(--text-muted)', marginTop: 4 }}>{formatFreq(freq)}</span>
    </div>
  );
}

function EqWaveform({ analyserData, bands }: { analyserData: Float32Array | null; bands: number[] }) {
  const bars = useMemo(() => {
    if (analyserData && analyserData.length > 0) {
      const step = Math.max(1, Math.floor(analyserData.length / 24));
      return Array.from({ length: 24 }, (_, index) => {
        const value = analyserData[Math.min(analyserData.length - 1, index * step)] || -90;
        return clamp((value + 90) / 90, 0.08, 1);
      });
    }
    return Array.from({ length: 24 }, (_, index) => {
      const gain = bands[index % Math.max(1, bands.length)] || 0;
      const shape = ((index % 6) - 2.5) * 0.035;
      return clamp(0.44 + (gain / 28) + shape, 0.16, 0.92);
    });
  }, [analyserData, bands]);

  return (
    <div className="eq-waveform" aria-hidden="true">
      {bars.map((value, index) => (
        <span key={index} style={{ height: `${Math.round(value * 100)}%`, animationDelay: `${index * 38}ms` }} />
      ))}
    </div>
  );
}

export function EqualizerView({
  eqConfig,
  analyserData,
}: {
  eqConfig: EqConfig | null;
  analyserData: Float32Array | null;
}) {
  const cfg: EqConfig = useMemo(() => eqConfig ?? {
      enabled: true,
      maxCustomPresets: 5,
      bands: FALLBACK_BANDS,
      bandMinDb: -12,
      bandMaxDb: 12,
      preampMinDb: -12,
      preampMaxDb: 12,
      presets: [],
    }, [eqConfig]);

  const [profile, setProfile] = useState<EqProfile>(makeFlatProfile(cfg.bands.length));
  const [newPresetName, setNewPresetName] = useState('');
  const [linked, setLinked] = useState(false);
  const [linkAllowed, setLinkAllowed] = useState(true);
  const [selectedHandle, setSelectedHandle] = useState<string | null>(null);
  const [selectedLabel, setSelectedLabel] = useState('No device selected');
  const selectedHandleRef = useRef<string | null>(null);
  const saveTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const pendingSave = useRef<{ profile: EqProfile; linked: boolean; handle: string | null } | null>(null);

  useEffect(() => {
    setProfile(current => normalizeProfile(current, cfg));
  }, [cfg]);

  useEffect(() => {
    selectedHandleRef.current = selectedHandle;
  }, [selectedHandle]);

  const scheduleSave = (nextProfile: EqProfile, linkedTarget = linked, handleTarget = selectedHandle) => {
    pendingSave.current = { profile: nextProfile, linked: linkedTarget, handle: handleTarget };
    if (saveTimer.current) clearTimeout(saveTimer.current);
    saveTimer.current = setTimeout(() => {
      const pending = pendingSave.current;
      if (!pending) return;
      if (pending.linked && pending.handle) {
        void sendNuiMessage('saveDeviceEqProfile', { handle: pending.handle, profile: pending.profile });
      } else {
        void sendNuiMessage('saveEqProfile', pending.profile);
      }
      pendingSave.current = null;
    }, 500);
  };

  const applyPatch = (patch: Partial<EqProfile>) => {
    setProfile(previous => {
      const next = normalizeProfile({ ...previous, ...patch }, cfg);
      scheduleSave(next);
      return next;
    });
  };

  useEffect(() => {
    const handler = (event: any) => {
      const raw = event.detail?.profile;
      if (raw && typeof raw === 'object') {
        setProfile(normalizeProfile(raw, cfg));
      }
    };
    window.addEventListener('pmms:eqProfile', handler);
    return () => window.removeEventListener('pmms:eqProfile', handler);
  }, [cfg]);

  useEffect(() => {
    const handler = (event: any) => {
      const detail = event.detail ?? {};
      const hasHandleSignal = Object.prototype.hasOwnProperty.call(detail, 'activePlayerHandle')
        || Object.prototype.hasOwnProperty.call(detail, 'selectedHandle');
      let nextHandle = selectedHandleRef.current;
      if (hasHandleSignal) {
        const handle = detail.activePlayerHandle ?? detail.selectedHandle ?? null;
        nextHandle = handle != null ? String(handle) : null;
        selectedHandleRef.current = nextHandle;
        setSelectedHandle(previous => {
          if (previous !== nextHandle) {
            setLinked(false);
            setLinkAllowed(true);
          }
          return nextHandle;
        });
      }

      if (nextHandle == null) {
        if (hasHandleSignal) {
          setSelectedLabel(previous => previous === 'No device selected' ? previous : 'No device selected');
        }
        return;
      }

      const rows = [
        ...(Array.isArray(detail.usableMediaPlayers) ? detail.usableMediaPlayers : []),
        ...(Array.isArray(detail.adminState?.devices) ? detail.adminState.devices : []),
      ];
      const match = rows.find((row: any) => String(row.handle) === String(nextHandle));
      const label = match?.label || `Device #${nextHandle}`;
      setSelectedLabel(previous => previous === label ? previous : label);
    };
    window.addEventListener('pmms:adminUpdate', handler);
    return () => window.removeEventListener('pmms:adminUpdate', handler);
  }, []);

  useEffect(() => {
    const handler = (event: any) => {
      const detail = event.detail ?? {};
      if (selectedHandle && String(detail.handle) !== String(selectedHandle)) return;
      setLinkAllowed(detail.allowed !== false);
      if (detail.allowed === false) {
        setLinked(false);
        return;
      }
      if (detail.profile && typeof detail.profile === 'object') {
        setProfile(normalizeProfile(detail.profile, cfg));
      }
    };
    window.addEventListener('pmms:eqDeviceProfile', handler);
    return () => window.removeEventListener('pmms:eqDeviceProfile', handler);
  }, [selectedHandle, cfg]);

  useEffect(() => {
    void sendNuiMessage('setEqAnalyserActive', { active: true });
    return () => {
      void sendNuiMessage('setEqAnalyserActive', { active: false });
    };
  }, []);

  const toggleLinked = () => {
    if (!selectedHandle) return;
    const nextLinked = !linked;
    setLinked(nextLinked);
    setLinkAllowed(true);
    if (nextLinked) {
      void sendNuiMessage('saveDeviceEqProfile', { handle: selectedHandle, profile });
    } else {
      scheduleSave(profile, false, null);
    }
  };

  const updateBand = (index: number, value: number) => {
    const bands = normalizePresetBands(profile.bands, cfg);
    bands[index] = clamp(value, cfg.bandMinDb, cfg.bandMaxDb);
    applyPatch({ bands });
  };

  const applyPreset = (preset: EqPreset) => {
    applyPatch({
      bands: normalizePresetBands(preset.bands, cfg),
      preampDb: clamp(Number(preset.preampDb) || 0, cfg.preampMinDb, cfg.preampMaxDb),
      highpassEnabled: preset.highpassEnabled === true,
      compressorEnabled: preset.compressorEnabled === true,
    });
  };

  const resetAll = () => applyPatch({
    bands: Array(cfg.bands.length).fill(0),
    preampDb: 0,
    highpassEnabled: false,
    compressorEnabled: false,
  });

  const saveCustomPreset = () => {
    const label = newPresetName.trim();
    if (!label) return;
    const existing = profile.customPresets ?? [];
    if (existing.length >= cfg.maxCustomPresets) return;
    setNewPresetName('');
    applyPatch({
      customPresets: [
        ...existing,
        {
          id: `custom_${Date.now()}`,
          label,
          preampDb: profile.preampDb,
          highpassEnabled: profile.highpassEnabled,
          compressorEnabled: profile.compressorEnabled,
          bands: [...profile.bands],
        },
      ],
    });
  };

  const deleteCustomPreset = (id: string) => {
    applyPatch({ customPresets: (profile.customPresets ?? []).filter(preset => preset.id !== id) });
  };

  const bands = normalizePresetBands(profile.bands, cfg);
  const builtins: EqPreset[] = cfg.presets ?? [];
  const customs: EqPreset[] = profile.customPresets ?? [];

  return (
    <div id="view-equalizer" className="view" style={{ paddingBottom: 32 }}>
      <div className="view-header">
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, minWidth: 0 }}>
          <h2>Equalizer</h2>
          <EqWaveform analyserData={analyserData} bands={bands} />
        </div>
        <div className="view-header-actions" style={{ gap: 10 }}>
          <button className="btn-outline btn-sm" onClick={resetAll}>Reset</button>
          <button className={linked ? 'btn-accent btn-sm' : 'btn-outline btn-sm'} disabled={!selectedHandle || !linkAllowed} onClick={toggleLinked}>
            Send to device (everyone)
          </button>
          <div
            onClick={() => applyPatch({ enabled: !profile.enabled })}
            role="switch"
            aria-checked={profile.enabled}
            style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer', userSelect: 'none', fontSize: 13 }}
          >
            <span style={{ color: 'var(--text-muted)' }}>EQ {profile.enabled ? 'ON' : 'OFF'}</span>
            <div style={{ width: 38, height: 22, borderRadius: 11, background: profile.enabled ? 'var(--accent)' : 'rgba(255,255,255,0.12)', position: 'relative', transition: 'background 0.2s' }}>
              <div style={{ position: 'absolute', top: 4, left: profile.enabled ? 18 : 4, width: 14, height: 14, borderRadius: '50%', background: '#fff', transition: 'left 0.18s' }} />
            </div>
          </div>
        </div>
      </div>
      <div style={{ marginTop: -6, marginBottom: 12, fontSize: 12, color: linked ? 'var(--accent)' : 'var(--text-muted)' }}>
        {linked ? `Sending changes to ${selectedLabel}` : selectedHandle ? `Local profile - selected ${selectedLabel}` : 'Local profile'}
      </div>
      <div style={{ display: 'flex', gap: 4, padding: '10px 4px', background: 'var(--bg-card)', borderRadius: 8, border: '1px solid var(--border)', opacity: profile.enabled ? 1 : 0.55, transition: 'opacity 0.2s' }}>
        {cfg.bands.map((freq, index) => (
          <BandSlider
            key={`${freq}-${index}`}
            freq={freq}
            value={bands[index] ?? 0}
            min={cfg.bandMinDb}
            max={cfg.bandMaxDb}
            onChange={value => updateBand(index, value)}
          />
        ))}
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16, marginTop: 14, padding: '14px 16px', background: 'var(--bg-card)', borderRadius: 8, border: '1px solid var(--border)' }}>
        <div className="admin-field">
          <span>Preamp <strong style={{ color: profile.preampDb === 0 ? 'var(--text-muted)' : profile.preampDb > 0 ? 'var(--accent)' : 'var(--red)' }}>{profile.preampDb > 0 ? '+' : ''}{profile.preampDb} dB</strong></span>
          <input
            type="range"
            min={cfg.preampMinDb}
            max={cfg.preampMaxDb}
            step={0.5}
            value={profile.preampDb}
            onChange={event => applyPatch({ preampDb: parseFloat(event.target.value) })}
          />
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10, justifyContent: 'center' }}>
          <label style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 13, cursor: 'pointer' }}>
            <input type="checkbox" checked={profile.highpassEnabled} onChange={event => applyPatch({ highpassEnabled: event.target.checked })} style={{ accentColor: 'var(--accent)', width: 14, height: 14 }} />
            High-Pass (80 Hz)
          </label>
          <label style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 13, cursor: 'pointer' }}>
            <input type="checkbox" checked={profile.compressorEnabled} onChange={event => applyPatch({ compressorEnabled: event.target.checked })} style={{ accentColor: 'var(--accent)', width: 14, height: 14 }} />
            Limiter / Compressor
          </label>
        </div>
      </div>
      <div style={{ marginTop: 20 }}>
        <div className="section-row" style={{ marginBottom: 8 }}>
          <span className="section-title">Built-in Presets</span>
        </div>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
          {builtins.map(preset => (
            <button key={preset.id} className="pill-btn" onClick={() => applyPreset(preset)} style={{ fontSize: 12 }}>
              {preset.label}
            </button>
          ))}
          {builtins.length === 0 && <span style={{ fontSize: 12, color: 'var(--text-muted)' }}>No presets configured.</span>}
        </div>
      </div>
      <div style={{ marginTop: 20 }}>
        <div className="section-row" style={{ marginBottom: 8 }}>
          <span className="section-title">Custom Presets</span>
          <span className="section-count">{customs.length}/{cfg.maxCustomPresets}</span>
        </div>
        {customs.length > 0 && (
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginBottom: 10 }}>
            {customs.map(preset => (
              <div key={preset.id} style={{ display: 'flex', alignItems: 'center', gap: 3 }}>
                <button className="pill-btn" style={{ fontSize: 12 }} onClick={() => applyPreset(preset)}>
                  {preset.label}
                </button>
                <button onClick={() => deleteCustomPreset(preset.id)} title="Delete" style={{ background: 'none', border: 'none', color: 'var(--red)', cursor: 'pointer', fontSize: 13, padding: '1px 4px', lineHeight: 1 }}>
                  x
                </button>
              </div>
            ))}
          </div>
        )}
        {customs.length < cfg.maxCustomPresets ? (
          <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
            <input
              type="text"
              placeholder="Name for current settings..."
              value={newPresetName}
              maxLength={40}
              onChange={event => setNewPresetName(event.target.value)}
              onKeyDown={event => {
                if (event.key === 'Enter') saveCustomPreset();
              }}
              style={{ flex: 1, fontSize: 13, background: 'var(--bg-input)', border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', color: 'var(--text-primary)', padding: '7px 10px', fontFamily: 'inherit', outline: 'none' }}
            />
            <button className="btn-accent btn-sm" disabled={!newPresetName.trim()} onClick={saveCustomPreset}>Save Current</button>
          </div>
        ) : (
          <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>Maximum {cfg.maxCustomPresets} custom presets. Delete one to save another.</div>
        )}
      </div>
    </div>
  );
}
