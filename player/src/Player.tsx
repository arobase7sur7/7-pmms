import { useCallback, useEffect, useRef, useState } from 'react';
import ReactPlayer from 'react-player';

type Command =
  | { source: 'pmms-nui'; type: 'PLAY'; url: string; volume?: number; muted?: boolean; startAt?: number }
  | { source: 'pmms-nui'; type: 'PAUSE' }
  | { source: 'pmms-nui'; type: 'RESUME' }
  | { source: 'pmms-nui'; type: 'STOP' }
  | { source: 'pmms-nui'; type: 'SEEK'; position: number }
  | { source: 'pmms-nui'; type: 'VOLUME'; volume: number; muted?: boolean };

type PlayerEvent =
  | { type: 'READY'; duration: number }
  | { type: 'PLAYING' }
  | { type: 'PAUSED' }
  | { type: 'ENDED' }
  | { type: 'BUFFERING' }
  | { type: 'BUFFER_END' }
  | { type: 'PROGRESS'; position: number }
  | { type: 'DURATION'; duration: number }
  | { type: 'ERROR'; code: string };

function clampVolume(value: unknown) {
  const volume = Number(value);
  if (!Number.isFinite(volume)) return 0.5;
  return Math.max(0, Math.min(1, volume));
}

function getErrorCode(error: unknown) {
  const text = String(error instanceof Error ? error.message : error);
  if (text.includes('150') || text.includes('101')) return 'EMBED_BLOCKED';
  if (text.toLowerCase().includes('not allowed')) return 'AUTOPLAY_BLOCKED';
  return 'PLAYBACK_ERROR';
}

export default function Player() {
  const [url, setUrl] = useState<string | undefined>(undefined);
  const [playing, setPlaying] = useState(false);
  const [volume, setVolume] = useState(0.5);
  const [muted, setMuted] = useState(false);
  const playerRef = useRef<ReactPlayer>(null);
  const pendingSeek = useRef<number | null>(null);

  const emit = useCallback((event: PlayerEvent) => {
    window.parent.postMessage({ source: 'pmms-player', ...event }, '*');
  }, []);

  useEffect(() => {
    function onMessage(event: MessageEvent) {
      if (event.data?.source !== 'pmms-nui') return;

      const command = event.data as Command;
      switch (command.type) {
        case 'PLAY':
          pendingSeek.current = Number.isFinite(Number(command.startAt)) ? Math.max(0, Number(command.startAt)) : null;
          setUrl(command.url);
          {
            const nextVolume = clampVolume(command.volume);
            setVolume(nextVolume);
            setMuted(command.muted === true || nextVolume <= 0);
          }
          setPlaying(true);
          break;
        case 'PAUSE':
          setPlaying(false);
          break;
        case 'RESUME':
          setPlaying(true);
          break;
        case 'STOP':
          setUrl(undefined);
          setPlaying(false);
          setMuted(false);
          pendingSeek.current = null;
          break;
        case 'SEEK':
          playerRef.current?.seekTo(Math.max(0, Number(command.position) || 0), 'seconds');
          break;
        case 'VOLUME':
          {
            const nextVolume = clampVolume(command.volume);
            setVolume(nextVolume);
            setMuted(command.muted === true || nextVolume <= 0);
          }
          break;
      }
    }

    window.addEventListener('message', onMessage);
    return () => window.removeEventListener('message', onMessage);
  }, []);

  return (
    <ReactPlayer
      ref={playerRef}
      url={url}
      playing={playing}
      volume={volume}
      muted={muted}
      width="100%"
      height="100%"
      playsinline
      config={{
        youtube: {
          playerVars: {
            autoplay: 1,
            origin: window.location.origin,
            playsinline: 1,
            rel: 0,
          },
          embedOptions: {
            host: 'https://www.youtube-nocookie.com',
          },
        },
        twitch: {
          options: {
            parent: [window.location.hostname],
          },
        },
      }}
      onReady={(player) => {
        const duration = Number(player.getDuration()) || 0;
        emit({ type: 'READY', duration });
        if (pendingSeek.current !== null) {
          player.seekTo(pendingSeek.current, 'seconds');
          pendingSeek.current = null;
        }
      }}
      onPlay={() => emit({ type: 'PLAYING' })}
      onPause={() => emit({ type: 'PAUSED' })}
      onEnded={() => emit({ type: 'ENDED' })}
      onBuffer={() => emit({ type: 'BUFFERING' })}
      onBufferEnd={() => emit({ type: 'BUFFER_END' })}
      onDuration={(duration) => emit({ type: 'DURATION', duration })}
      onProgress={({ playedSeconds }) => emit({ type: 'PROGRESS', position: playedSeconds })}
      onError={(error) => emit({ type: 'ERROR', code: getErrorCode(error) })}
    />
  );
}
