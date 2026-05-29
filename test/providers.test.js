const invidiousSeeds = ['https://inv.nadeko.net', 'https://invidious.privacydev.net', 'https://vid.puffyan.us', 'https://inv.thepixora.com'];
const pipedSeeds = ['https://api.piped.private.coffee', 'https://pipedapi.kavin.rocks', 'https://piped-api.privacy.com.de'];

const standardVideoId = 'dQw4w9WgXcQ';
const blockedVideoId = 'w8QPV9_KVbk';

async function probeUrl(url) {
  try {
    let response = await fetch(url, {
      method: 'HEAD',
      signal: AbortSignal.timeout(4000),
      redirect: 'follow',
    });
    if (!response.ok || response.status === 405) {
      response = await fetch(url, {
        method: 'GET',
        headers: { Range: 'bytes=0-0' },
        signal: AbortSignal.timeout(4000),
        redirect: 'follow',
      });
    }
    const contentType = response.headers.get('content-type') ?? '';
    return {
      ok: response.ok && /audio|video|octet-stream|mpegurl|ogg/.test(contentType),
      status: response.status,
      contentType,
    };
  } catch (error) {
    return { ok: false, status: 0, error: error.message };
  }
}

function uniqueUrls(urls) {
  return [...new Set(urls.filter(Boolean).map((url) => String(url).replace(/\/+$/, '')))];
}

async function getInvidiousHosts() {
  try {
    const response = await fetch('https://api.invidious.io/instances.json?sort_by=health', { signal: AbortSignal.timeout(8000) });
    if (!response.ok) return invidiousSeeds;
    const instances = await response.json();
    const discovered = instances
      .filter(([, details]) => details?.type === 'https' && details?.api === true && details?.monitor?.down === false)
      .map(([, details]) => details.uri);
    return uniqueUrls([...discovered, ...invidiousSeeds]);
  } catch {
    return invidiousSeeds;
  }
}

async function getPipedHosts() {
  try {
    const response = await fetch('https://piped-instances.kavin.rocks/', { signal: AbortSignal.timeout(8000) });
    if (!response.ok) return pipedSeeds;
    const instances = await response.json();
    const discovered = instances
      .filter((details) => details?.api_url && Number(details.uptime_24h) >= 90)
      .map((details) => details.api_url);
    return uniqueUrls([...discovered, ...pipedSeeds]);
  } catch {
    return pipedSeeds;
  }
}

async function testInvidious(id) {
  const hosts = await getInvidiousHosts();
  for (const host of hosts) {
    try {
      const startedAt = Date.now();
      const response = await fetch(`${host}/api/v1/videos/${id}`, { signal: AbortSignal.timeout(8000) });
      if (!response.ok) continue;
      const payload = await response.json();
      const audio = payload.adaptiveFormats
        ?.filter((format) => format.type?.startsWith('audio/'))
        .sort((left, right) => right.bitrate - left.bitrate)[0];
      if (!audio?.url) continue;
      const probe = await probeUrl(audio.url);
      return { ok: probe.ok, ms: Date.now() - startedAt, host, status: probe.status, contentType: probe.contentType };
    } catch {
      continue;
    }
  }
  return { ok: false };
}

async function testPiped(id) {
  const hosts = await getPipedHosts();
  for (const host of hosts) {
    try {
      const startedAt = Date.now();
      const response = await fetch(`${host}/streams/${id}`, { signal: AbortSignal.timeout(8000) });
      if (!response.ok) continue;
      const payload = await response.json();
      const stream = [
        ...(payload.audioStreams ?? []),
        ...(payload.videoStreams ?? []).filter((candidate) => candidate.videoOnly !== true),
      ].sort((left, right) => right.bitrate - left.bitrate)[0];
      if (!stream?.url) continue;
      const probe = await probeUrl(stream.url);
      return { ok: probe.ok, ms: Date.now() - startedAt, host, status: probe.status, contentType: probe.contentType };
    } catch {
      continue;
    }
  }
  return { ok: false };
}

async function testCobalt(url) {
  try {
    const startedAt = Date.now();
    const response = await fetch('https://api.cobalt.tools/', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify({ url, downloadMode: 'audio', disableMetadata: true, alwaysProxy: true }),
      signal: AbortSignal.timeout(10000),
    });
    const payload = await response.json();
    if (!response.ok) return { ok: false, status: response.status, error: payload?.error?.code };
    if (!['stream', 'redirect', 'tunnel'].includes(payload.status)) return { ok: false, cobaltStatus: payload.status };
    const probe = await probeUrl(payload.url);
    return { ok: probe.ok, ms: Date.now() - startedAt, status: probe.status, contentType: probe.contentType };
  } catch (error) {
    return { ok: false, error: error.message };
  }
}

function extractPlayerResponse(html) {
  const marker = 'ytInitialPlayerResponse';
  const markerIndex = html.indexOf(marker);
  if (markerIndex === -1) return null;
  const assignmentIndex = html.indexOf('{', markerIndex);
  if (assignmentIndex === -1) return null;

  let depth = 0;
  let inString = false;
  let escaped = false;

  for (let index = assignmentIndex; index < html.length; index += 1) {
    const char = html[index];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (char === '\\') {
        escaped = true;
      } else if (char === '"') {
        inString = false;
      }
      continue;
    }

    if (char === '"') {
      inString = true;
    } else if (char === '{') {
      depth += 1;
    } else if (char === '}') {
      depth -= 1;
      if (depth === 0) {
        return html.slice(assignmentIndex, index + 1);
      }
    }
  }

  return null;
}

async function testPageScrape(id) {
  try {
    const startedAt = Date.now();
    const response = await fetch(`https://www.youtube.com/watch?v=${id}`, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Accept-Language': 'en-US',
      },
      signal: AbortSignal.timeout(10000),
    });
    const html = await response.text();
    const rawPlayer = extractPlayerResponse(html);
    if (!rawPlayer) return { ok: false, error: 'pattern not found' };
    const player = JSON.parse(rawPlayer);
    if (player?.playabilityStatus?.status !== 'OK') return { ok: false, status: player?.playabilityStatus?.status };
    const formats = [...(player?.streamingData?.adaptiveFormats ?? []), ...(player?.streamingData?.formats ?? [])];
    const audio = formats.filter((format) => format.mimeType?.startsWith('audio/')).sort((left, right) => right.bitrate - left.bitrate)[0];
    if (!audio?.url) return { ok: false, error: 'no audio format' };
    const probe = await probeUrl(audio.url);
    return { ok: probe.ok, ms: Date.now() - startedAt, status: probe.status, contentType: probe.contentType };
  } catch (error) {
    return { ok: false, error: error.message };
  }
}

async function run() {
  console.log('\n=== Fallback Provider Tests ===');
  for (const [label, id] of [['Standard video', standardVideoId], ['Mix/blocked video', blockedVideoId]]) {
    console.log(`\n--- ${label} (${id}) ---`);
    const [invidious, piped, cobalt, pageScrape] = await Promise.all([
      testInvidious(id),
      testPiped(id),
      testCobalt(`https://www.youtube.com/watch?v=${id}`),
      testPageScrape(id),
    ]);
    console.log(`  Invidious:  ${invidious.ok ? 'PASS' : 'FAIL'}  ${invidious.ms ?? '-'}ms  ${invidious.host ?? invidious.error ?? invidious.status ?? ''}`);
    console.log(`  Piped:      ${piped.ok ? 'PASS' : 'FAIL'}  ${piped.ms ?? '-'}ms  ${piped.host ?? piped.error ?? piped.status ?? ''}`);
    console.log(`  Cobalt:     ${cobalt.ok ? 'PASS' : 'FAIL'}  ${cobalt.ms ?? '-'}ms  ${cobalt.error ?? cobalt.cobaltStatus ?? cobalt.status ?? ''}`);
    console.log(`  PageScrape: ${pageScrape.ok ? 'PASS' : 'FAIL'}  ${pageScrape.ms ?? '-'}ms  ${pageScrape.error ?? pageScrape.status ?? ''}`);
  }
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
