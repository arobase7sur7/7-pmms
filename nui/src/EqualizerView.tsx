import React, { useEffect, useRef, useState } from 'react';
import { sendNuiMessage } from './nuiBridge';

// ── Types ─────────────────────────────────────────────────────────────────────

interface EqPreset {
  id: string;
  label: string;
  bands: number[];
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

// ── Defaults ──────────────────────────────────────────────────────────────────

const DEFAULT_BANDS = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
const BAND_FREQS    = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];

function makeFlatProfile(): EqProfile {
  return {
    enabled: false,
    preampDb: 0,
    highpassEnabled: false,
    compressorEnabled: false,
    bands: [...DEFAULT_BANDS],
    customPresets: [],
  };
}

function formatFreq(hz: number): string {
  return hz >= 1000 ? `${hz / 1000}k` : `${hz}`;
}

function clamp(v: number, lo: number, hi: number) {
  return Math.max(lo, Math.min(hi, v));
}

// ── Spectrum canvas ───────────────────────────────────────────────────────────

function SpectrumCanvas({ data }: { data: Float32Array | null }) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const W = canvas.width;
    const H = canvas.height;
    ctx.clearRect(0, 0, W, H);

    if (!data || data.length === 0) {
      ctx.fillStyle = 'rgba(255,255,255,0.04)';
      ctx.fillRect(0, 0, W, H);
      // Draw idle flat line
      ctx.strokeStyle = 'rgba(104,216,166,0.2)';
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(0, H / 2);
      ctx.lineTo(W, H / 2);
      ctx.stroke();
      return;
    }

    const barCount = Math.min(data.length, 64);
    const barWidth = W / barCount;
    const gradient = ctx.createLinearGradient(0, H, 0, 0);
    gradient.addColorStop(0, 'rgba(104,216,166,0.85)');
    gradient.addColorStop(0.5, 'rgba(104,216,166,0.5)');
    gradient.addColorStop(1, 'rgba(104,216,166,0.2)');

    ctx.fillStyle = 'rgba(10,16,14,0.7)';
    ctx.fillRect(0, 0, W, H);

    ctx.fillStyle = gradient;
    for (let i = 0; i < barCount; i++) {
      const db = data[i];
      const normalized = Math.max(0, (db + 90) / 90);
      const barH = normalized * H;
      ctx.fillRect(i * barWidth + 0.5, H - barH, Math.max(1, barWidth - 1.5), barH);
    }
  }, [data]);

  return (
    <canvas
      ref={canvasRef}
      width={512}
      height={64}
      style={{ width: '100%', height: 64, borderRadius: 6, display: 'block' }}
    />
  );
}

// ── Single vertical band slider ───────────────────────────────────────────────

function BandSlider({
  freq, value, min, max, disabled, onChange,
}: {
  freq: number; value: number; min: number; max: number; disabled: boolean;
  onChange: (v: number) => void;
}) {
  const rounded = Math.round(value * 2) / 2; // 0.5 step display
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 3, flex: '1 1 0', minWidth: 0 }}>
      <span style={{ fontSize: 10, color: value === 0 ? 'var(--text-muted)' : value > 0 ? 'var(--accent)' : 'var(--red)', fontWeight: 700, minHeight: 14 }}>
        {value === 0 ? '0' : value > 0 ? `+${rounded}` : `${rounded}`}
      </span>
      <input
        type="range"
        min={min}
        max={max}
        step={0.5}
        value={value}
        disabled={disabled}
        onChange={(e) => onChange(parseFloat(e.target.value))}
        style={{
          appearance: 'slider-vertical',
          WebkitAppearance: 'slider-vertical',
          height: 110,
          width: 22,
          cursor: disabled ? 'default' : 'pointer',
          accentColor: 'var(--accent)',
        }}
      />
      <span style={{ fontSize: 9, color: 'var(--text-muted)' }}>{formatFreq(freq)}</span>
    </div>
  );
}

// ── Main EQ view ──────────────────────────────────────────────────────────────

export function EqualizerView({
  eqConfig,
  analyserData,
}: {
  eqConfig: EqConfig | null;
  analyserData: Float32Array | null;
}) {
  const cfg: EqConfig = eqConfig ?? {
    enabled: true,
    maxCustomPresets: 5,
    bands: BAND_FREQS,
    bandMinDb: -12,
    bandMaxDb: 12,
    preampMinDb: -12,
    preampMaxDb: 12,
    presets: [],
  };

  const [profile, setProfile] = useState<EqProfile>(makeFlatProfile());
  const [newPresetName, setNewPresetName] = useState('');

  // ── debounced save to server ───────────────────────────────────────────────
  const saveTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const pendingSave = useRef<EqProfile | null>(null);

  const scheduleSave = (p: EqProfile) => {
    pendingSave.current = p;
    if (saveTimer.current) clearTimeout(saveTimer.current);
    saveTimer.current = setTimeout(() => {
      if (pendingSave.current) {
        void sendNuiMessage('saveEqProfile', pendingSave.current);
        pendingSave.current = null;
      }
    }, 500);
  };

  // Apply a patch and trigger persist + DUI update
  const applyPatch = (patch: Partial<EqProfile>) => {
    setProfile(prev => {
      const next = { ...prev, ...patch };
      scheduleSave(next);
      return next;
    });
  };

  // ── receive profile from server ────────────────────────────────────────────
  useEffect(() => {
    const handler = (e: any) => {
      const p = e.detail?.profile;
      if (p && typeof p === 'object') {
        // Ensure bands array is always 10 long
        const bands = Array.isArray(p.bands) ? p.bands.slice(0, 10) : [...DEFAULT_BANDS];
        while (bands.length < 10) bands.push(0);
        setProfile({ ...makeFlatProfile(), ...p, bands });
      }
    };
    window.addEventListener('pmms:eqProfile', handler);
    return () => window.removeEventListener('pmms:eqProfile', handler);
  }, []);

  // ── analyser streaming ─────────────────────────────────────────────────────
  useEffect(() => {
    void sendNuiMessage('setEqAnalyserActive', { active: true });
    return () => { void sendNuiMessage('setEqAnalyserActive', { active: false }); };
  }, []);

  // ── helpers ────────────────────────────────────────────────────────────────
  const updateBand = (i: number, v: number) => {
    const bands = [...(profile.bands ?? DEFAULT_BANDS)];
    bands[i] = clamp(v, cfg.bandMinDb, cfg.bandMaxDb);
    applyPatch({ bands });
  };

  // Presets can ALWAYS be applied (even when EQ is disabled) – they just set the values.
  const applyPreset = (preset: EqPreset) => {
    const bands = preset.bands.slice(0, 10);
    while (bands.length < 10) bands.push(0);
    applyPatch({ bands: [...bands] });
  };

  const resetAll = () => applyPatch({ bands: [...DEFAULT_BANDS], preampDb: 0 });

  const saveCustomPreset = () => {
    const label = newPresetName.trim();
    if (!label) return;
    const existing = profile.customPresets ?? [];
    if (existing.length >= cfg.maxCustomPresets) return;
    const id = `custom_${Date.now()}`;
    setNewPresetName('');
    applyPatch({ customPresets: [...existing, { id, label, bands: [...(profile.bands ?? DEFAULT_BANDS)] }] });
  };

  const deleteCustomPreset = (id: string) => {
    applyPatch({ customPresets: (profile.customPresets ?? []).filter(p => p.id !== id) });
  };

  const bands = profile.bands ?? DEFAULT_BANDS;
  const freqs = cfg.bands?.length === 10 ? cfg.bands : BAND_FREQS;
  const builtins: EqPreset[] = cfg.presets ?? [];
  const customs: EqPreset[] = profile.customPresets ?? [];
  const eqDisabled = !profile.enabled; // sliders disabled when EQ off, but presets still work

  return (
    <div id="view-equalizer" className="view" style={{ paddingBottom: 32 }}>
      {/* Header */}
      <div className="view-header">
        <h2>Equalizer</h2>
        <div className="view-header-actions" style={{ gap: 10 }}>
          <button className="btn-outline btn-sm" onClick={resetAll}>Reset</button>
          {/* Enable toggle */}
          <div
            onClick={() => applyPatch({ enabled: !profile.enabled })}
            role="switch"
            aria-checked={profile.enabled}
            style={{
              display: 'flex', alignItems: 'center', gap: 8,
              cursor: 'pointer', userSelect: 'none', fontSize: 13,
            }}
          >
            <span style={{ color: 'var(--text-muted)' }}>EQ {profile.enabled ? 'ON' : 'OFF'}</span>
            <div style={{
              width: 38, height: 22, borderRadius: 11,
              background: profile.enabled ? 'var(--accent)' : 'rgba(255,255,255,0.12)',
              position: 'relative', transition: 'background 0.2s',
            }}>
              <div style={{
                position: 'absolute', top: 4,
                left: profile.enabled ? 18 : 4,
                width: 14, height: 14, borderRadius: '50%',
                background: '#fff', transition: 'left 0.18s',
              }} />
            </div>
          </div>
        </div>
      </div>

      {/* Spectrum */}
      <div style={{ marginBottom: 16, borderRadius: 8, overflow: 'hidden', border: '1px solid var(--border)' }}>
        <SpectrumCanvas data={analyserData} />
      </div>

      {/* Band sliders – always interactive so you can set values before enabling */}
      <div style={{
        display: 'flex', gap: 4, padding: '10px 4px',
        background: 'var(--bg-card)', borderRadius: 8,
        border: '1px solid var(--border)',
        opacity: eqDisabled ? 0.55 : 1,
        transition: 'opacity 0.2s',
      }}>
        {freqs.map((freq, i) => (
          <BandSlider
            key={freq}
            freq={freq}
            value={bands[i] ?? 0}
            min={cfg.bandMinDb}
            max={cfg.bandMaxDb}
            disabled={false /* always draggable so you can set before enabling */}
            onChange={v => updateBand(i, v)}
          />
        ))}
      </div>

      {/* Preamp + processing */}
      <div style={{
        display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16,
        marginTop: 14, padding: '14px 16px',
        background: 'var(--bg-card)', borderRadius: 8,
        border: '1px solid var(--border)',
      }}>
        <div className="admin-field">
          <span>Preamp &nbsp;
            <strong style={{ color: profile.preampDb === 0 ? 'var(--text-muted)' : profile.preampDb > 0 ? 'var(--accent)' : 'var(--red)' }}>
              {profile.preampDb > 0 ? '+' : ''}{profile.preampDb} dB
            </strong>
          </span>
          <input
            type="range"
            min={cfg.preampMinDb}
            max={cfg.preampMaxDb}
            step={0.5}
            value={profile.preampDb}
            onChange={e => applyPatch({ preampDb: parseFloat(e.target.value) })}
          />
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10, justifyContent: 'center' }}>
          <label style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 13, cursor: 'pointer' }}>
            <input
              type="checkbox"
              checked={profile.highpassEnabled}
              onChange={e => applyPatch({ highpassEnabled: e.target.checked })}
              style={{ accentColor: 'var(--accent)', width: 14, height: 14 }}
            />
            High-Pass (80 Hz)
          </label>
          <label style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 13, cursor: 'pointer' }}>
            <input
              type="checkbox"
              checked={profile.compressorEnabled}
              onChange={e => applyPatch({ compressorEnabled: e.target.checked })}
              style={{ accentColor: 'var(--accent)', width: 14, height: 14 }}
            />
            Limiter / Compressor
          </label>
        </div>
      </div>

      {/* Built-in presets */}
      <div style={{ marginTop: 20 }}>
        <div className="section-row" style={{ marginBottom: 8 }}>
          <span className="section-title">Built-in Presets</span>
        </div>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
          {builtins.map(preset => (
            <button
              key={preset.id}
              className="pill-btn"
              onClick={() => applyPreset(preset)}
              style={{ fontSize: 12 }}
            >
              {preset.label}
            </button>
          ))}
          {builtins.length === 0 && (
            <span style={{ fontSize: 12, color: 'var(--text-muted)' }}>No presets configured.</span>
          )}
        </div>
      </div>

      {/* Custom presets */}
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
                <button
                  onClick={() => deleteCustomPreset(preset.id)}
                  title="Delete"
                  style={{
                    background: 'none', border: 'none',
                    color: 'var(--red)', cursor: 'pointer',
                    fontSize: 13, padding: '1px 4px', lineHeight: 1,
                  }}
                >
                  ×
                </button>
              </div>
            ))}
          </div>
        )}

        {customs.length < cfg.maxCustomPresets ? (
          <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
            <input
              type="text"
              placeholder="Name for current settings…"
              value={newPresetName}
              maxLength={40}
              onChange={e => setNewPresetName(e.target.value)}
              onKeyDown={e => { if (e.key === 'Enter') saveCustomPreset(); }}
              style={{
                flex: 1, fontSize: 13,
                background: 'var(--bg-input)',
                border: '1px solid var(--border)',
                borderRadius: 'var(--radius-sm)',
                color: 'var(--text-primary)',
                padding: '7px 10px',
                fontFamily: 'inherit',
                outline: 'none',
              }}
            />
            <button
              className="btn-accent btn-sm"
              disabled={!newPresetName.trim()}
              onClick={saveCustomPreset}
            >
              Save Current
            </button>
          </div>
        ) : (
          <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>
            Maximum {cfg.maxCustomPresets} custom presets. Delete one to save another.
          </div>
        )}
      </div>
    </div>
  );
}
