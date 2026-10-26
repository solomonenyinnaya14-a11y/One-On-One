"use client";

import { useEffect, useRef, useState, type MouseEvent } from "react";
import { sendVoiceMessage } from "@/app/(app)/actions";
import { createBrowserSupabase } from "@/lib/supabase/browser";

const BUCKET = "voice-messages";
const MAX_SECONDS = 120;
const MAX_BYTES = 20 * 1024 * 1024;
const WAVEFORM_BARS = 32;

function supportedMimeType() {
  if (typeof MediaRecorder === "undefined") return "";
  return ["audio/webm;codecs=opus", "audio/webm", "audio/mp4", "audio/ogg;codecs=opus", "audio/ogg"]
    .find((type) => MediaRecorder.isTypeSupported(type)) ?? "";
}

function fileExtension(type: string) {
  if (type.includes("mp4")) return { ext: "mp4", contentType: "audio/mp4" };
  if (type.includes("ogg")) return { ext: "ogg", contentType: "audio/ogg" };
  return { ext: "webm", contentType: "audio/webm" };
}

function formatTime(totalSeconds: number) {
  const mins = Math.floor(totalSeconds / 60).toString();
  const secs = Math.floor(totalSeconds % 60).toString().padStart(2, "0");
  return `${mins}:${secs}`;
}

function Waveform({ levels, active = false }: { levels: number[]; active?: boolean }) {
  const bars = levels.length ? levels.slice(-WAVEFORM_BARS) : Array.from({ length: WAVEFORM_BARS }, () => 0.12);
  return (
    <div className="flex h-8 min-w-0 flex-1 items-center justify-center gap-[2px]" aria-hidden="true">
      {Array.from({ length: WAVEFORM_BARS }, (_, index) => {
        const value = bars[index] ?? 0.12;
        return <span key={index} className={active ? "w-[3px] rounded-full bg-navy-900" : "w-[3px] rounded-full bg-current opacity-80"}
          style={{ height: `${Math.max(4, Math.round(value * 28))}px` }} />;
      })}
    </div>
  );
}

export function VoiceRecorder({ conversationId, userId, disabled, onSent }: {
  conversationId: string;
  userId: string;
  disabled: boolean;
  onSent: (id: string, path: string) => void;
}) {
  const recorder = useRef<MediaRecorder | null>(null);
  const stream = useRef<MediaStream | null>(null);
  const chunks = useRef<BlobPart[]>([]);
  const timeout = useRef<number | null>(null);
  const meterTimer = useRef<number | null>(null);
  const audioContext = useRef<AudioContext | null>(null);
  const analyser = useRef<AnalyserNode | null>(null);
  const previewUrlRef = useRef<string | null>(null);
  const pointerHeld = useRef(false);
  const lockedRef = useRef(false);
  const pointerStart = useRef<{ x: number; y: number } | null>(null);
  const [recording, setRecording] = useState(false);
  const [locked, setLocked] = useState(false);
  const [busy, setBusy] = useState(false);
  const [seconds, setSeconds] = useState(0);
  const [preview, setPreview] = useState<Blob | null>(null);
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);
  const [levels, setLevels] = useState<number[]>([]);
  const [error, setError] = useState<string | null>(null);

  function stopTracks() {
    stream.current?.getTracks().forEach((track) => track.stop());
    stream.current = null;
    if (meterTimer.current !== null) window.clearInterval(meterTimer.current);
    meterTimer.current = null;
    if (audioContext.current && audioContext.current.state !== "closed") void audioContext.current.close();
    audioContext.current = null;
    analyser.current = null;
  }

  function clearPreview() {
    if (previewUrlRef.current) URL.revokeObjectURL(previewUrlRef.current);
    previewUrlRef.current = null;
    setPreviewUrl(null);
    setPreview(null);
    setSeconds(0);
    setLevels([]);
  }

  useEffect(() => () => {
    if (timeout.current !== null) window.clearTimeout(timeout.current);
    if (meterTimer.current !== null) window.clearInterval(meterTimer.current);
    stream.current?.getTracks().forEach((track) => track.stop());
    if (audioContext.current && audioContext.current.state !== "closed") void audioContext.current.close();
    if (previewUrlRef.current) URL.revokeObjectURL(previewUrlRef.current);
  }, []);

  async function start() {
    setError(null);
    clearPreview();
    if (!navigator.mediaDevices?.getUserMedia || typeof MediaRecorder === "undefined") {
      setError("Voice recording isn't supported by this browser. Try the latest Safari or Chrome.");
      return;
    }
    const mimeType = supportedMimeType();
    if (!mimeType) {
      setError("This browser can't record a supported audio format.");
      return;
    }
    try {
      const media = await navigator.mediaDevices.getUserMedia({ audio: true });
      stream.current = media;
      chunks.current = [];
      setLevels([]);
      const rec = new MediaRecorder(media, { mimeType });
      recorder.current = rec;
      rec.ondataavailable = (event) => { if (event.data.size > 0) chunks.current.push(event.data); };
      rec.onerror = () => {
        setError("Recording stopped unexpectedly. Please try again.");
        setRecording(false);
        stopTracks();
      };
      rec.onstop = () => {
        stopTracks();
        setRecording(false);
        setLocked(false);
        const blob = new Blob(chunks.current, { type: mimeType });
        if (blob.size === 0) return;
        if (blob.size > MAX_BYTES) {
          setError("That voice note is too large to send. Try recording a shorter note.");
          return;
        }
        const url = URL.createObjectURL(blob);
        previewUrlRef.current = url;
        setPreview(blob);
        setPreviewUrl(url);
      };
      rec.start(200);
      setRecording(true);
      setSeconds(0);
      const startedAt = Date.now();
      const tick = () => {
        const elapsed = Math.min(MAX_SECONDS, Math.floor((Date.now() - startedAt) / 1000));
        setSeconds(elapsed);
        if (elapsed >= MAX_SECONDS) {
          if (rec.state !== "inactive") rec.stop();
        } else if (rec.state !== "inactive") {
          timeout.current = window.setTimeout(tick, 200);
        }
      };
      timeout.current = window.setTimeout(tick, 200);

      try {
        const AudioContextConstructor = window.AudioContext;
        if (AudioContextConstructor) {
          const context = new AudioContextConstructor();
          audioContext.current = context;
          const meter = context.createAnalyser();
          meter.fftSize = 64;
          analyser.current = meter;
          context.createMediaStreamSource(media).connect(meter);
          const samples = new Uint8Array(meter.frequencyBinCount);
          meterTimer.current = window.setInterval(() => {
            meter.getByteTimeDomainData(samples);
            let sum = 0;
            for (const sample of samples) sum += Math.abs(sample - 128);
            const amplitude = Math.max(0.12, Math.min(1, sum / samples.length / 40));
            setLevels((current) => [...current.slice(-(WAVEFORM_BARS - 1)), amplitude]);
          }, 100);
        }
      } catch {
        // Recording still works if the browser doesn't allow a live audio meter.
      }
    } catch {
      setError("Allow microphone access to record a voice note.");
      stopTracks();
    }
  }

  function stop() {
    if (timeout.current !== null) window.clearTimeout(timeout.current);
    timeout.current = null;
    if (recorder.current?.state === "recording") recorder.current.stop();
  }

  function cancel() {
    if (timeout.current !== null) window.clearTimeout(timeout.current);
    timeout.current = null;
    if (recorder.current?.state === "recording") {
      recorder.current.onstop = null;
      recorder.current.stop();
    }
    stopTracks();
    setRecording(false);
    setLocked(false);
    clearPreview();
    setError(null);
  }

  async function send() {
    if (!preview) return;
    setError(null);
    const supabase = createBrowserSupabase();
    if (!supabase) {
      setError("Audio storage isn't configured yet.");
      return;
    }
    setBusy(true);
    try {
      const { ext, contentType } = fileExtension(preview.type);
      const path = `${conversationId}/${userId}/${crypto.randomUUID()}.${ext}`;
      const { error: uploadError } = await supabase.storage.from(BUCKET).upload(path, preview, {
        contentType,
        cacheControl: "3600",
        upsert: false,
      });
      if (uploadError) {
        const detail = uploadError.message.toLowerCase();
        if (detail.includes("bucket") || detail.includes("not found")) {
          throw new Error("Voice messaging storage isn't set up on this preview yet. The database migration must be applied first.");
        }
        if (detail.includes("row-level security") || detail.includes("policy")) {
          throw new Error("Voice upload was blocked by storage permissions. The voice-message migration must be applied to this database.");
        }
        throw new Error(uploadError.message);
      }
      const result = await sendVoiceMessage(conversationId, path);
      if (result.error || !result.id) {
        setError(result.error ?? "Your voice note wasn't sent. Please try again.");
        return;
      }
      onSent(result.id, path);
      clearPreview();
    } catch (failure) {
      setError(failure instanceof Error && failure.message
        ? failure.message
        : "Your voice note wasn't sent. Check your connection and try again.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="flex min-w-0 flex-col items-stretch gap-1">
      {recording ? (
        <div className="flex min-h-12 min-w-0 items-center gap-2 rounded-full border border-grey-300 bg-grey-50 px-3 py-2">
          <span className="h-2.5 w-2.5 shrink-0 animate-pulse rounded-full bg-navy-900" aria-label="Recording" />
          <span className="shrink-0 font-mono text-sm font-semibold text-navy-900">{formatTime(seconds)}</span>
          <Waveform levels={levels} active />
          <button type="button" onClick={cancel} className="shrink-0 rounded-full px-2 py-1 text-xs font-semibold text-navy-900" aria-label="Discard recording">Cancel</button>
          <button type="button" onClick={() => setLocked((value) => !value)} className="shrink-0 rounded-full border border-grey-300 px-2 py-1 text-xs font-semibold text-navy-900" aria-pressed={locked}>
            {locked ? "Locked" : "Lock"}
          </button>
          <button type="button" onClick={stop} className="min-h-9 min-w-9 shrink-0 rounded-full bg-navy-900 px-3 text-sm font-bold text-white" aria-label="Finish recording">✓</button>
        </div>
      ) : previewUrl ? (
        <div className="flex min-h-12 min-w-0 items-center gap-2 rounded-2xl border border-grey-300 bg-grey-50 p-2">
          <VoiceWavePlayer src={previewUrl} preview />
          <button type="button" onClick={clearPreview} disabled={busy} className="min-h-9 rounded-full px-2 text-xs font-semibold text-red-700 disabled:opacity-50" aria-label="Delete recording">Delete</button>
          <button type="button" onClick={() => void send()} disabled={busy} className="min-h-9 rounded-full bg-navy-900 px-3 text-xs font-semibold text-white disabled:opacity-50">
            {busy ? "Sending…" : "Send"}
          </button>
        </div>
      ) : (
        <button type="button" onClick={() => void start()} disabled={disabled || busy}
          aria-label="Record a voice message"
          className="min-h-12 min-w-12 rounded-full border-2 border-navy-900 px-3 text-sm font-semibold disabled:opacity-50">
          🎙️
        </button>
      )}
      {recording ? <p className="text-center text-[11px] text-grey-600">{locked ? "Recording hands-free · tap ✓ when finished" : "Recording… release to finish · slide up to lock · slide left to cancel"}</p> : null}
      {error ? <p role="alert" className="max-w-72 text-right text-xs font-medium text-red-700">{error}</p> : null}
    </div>
  );
}

function VoiceWavePlayer({ src, mine = false, preview = false }: { src: string; mine?: boolean; preview?: boolean }) {
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const [playing, setPlaying] = useState(false);
  const [duration, setDuration] = useState(0);
  const [currentTime, setCurrentTime] = useState(0);
  const [playError, setPlayError] = useState(false);
  const progress = duration > 0 ? Math.min(1, currentTime / duration) : 0;
  const bars = Array.from({ length: WAVEFORM_BARS }, (_, index) => {
    // Deterministic varied bar heights give the compact voice-note waveform its shape.
    const shape = (Math.sin((index + 2) * 1.73) + 1) / 2;
    return 5 + Math.round(shape * 19);
  });

  useEffect(() => {
    setPlaying(false);
    setCurrentTime(0);
    setDuration(0);
    setPlayError(false);
  }, [src]);

  async function togglePlayback() {
    const audio = audioRef.current;
    if (!audio) return;
    setPlayError(false);
    if (audio.paused) {
      try {
        await audio.play();
      } catch {
        setPlayError(true);
      }
    } else {
      audio.pause();
    }
  }

  function seek(event: MouseEvent<HTMLButtonElement>) {
    const audio = audioRef.current;
    if (!audio || !Number.isFinite(audio.duration) || audio.duration <= 0) return;
    const rect = event.currentTarget.getBoundingClientRect();
    const ratio = Math.max(0, Math.min(1, (event.clientX - rect.left) / rect.width));
    audio.currentTime = ratio * audio.duration;
    setCurrentTime(audio.currentTime);
  }

  const foreground = mine ? "text-white" : "text-navy-900";
  const muted = mine ? "text-white/65" : "text-grey-600";
  const activeBar = mine ? "bg-white" : "bg-navy-900";
  const inactiveBar = mine ? "bg-white/35" : "bg-grey-300";

  return (
    <div className={`flex min-w-0 items-center gap-3 ${preview ? "w-full" : "min-w-[210px] max-w-[280px]"}`}>
      <audio
        ref={audioRef}
        src={src}
        preload="metadata"
        className="hidden"
        onLoadedMetadata={(event) => setDuration(Number.isFinite(event.currentTarget.duration) ? event.currentTarget.duration : 0)}
        onDurationChange={(event) => setDuration(Number.isFinite(event.currentTarget.duration) ? event.currentTarget.duration : 0)}
        onTimeUpdate={(event) => setCurrentTime(event.currentTarget.currentTime)}
        onPlay={() => setPlaying(true)}
        onPause={() => setPlaying(false)}
        onEnded={() => { setPlaying(false); setCurrentTime(0); if (audioRef.current) audioRef.current.currentTime = 0; }}
        onError={() => setPlayError(true)}
      />
      <button type="button" onClick={() => void togglePlayback()} aria-label={playing ? "Pause voice note" : "Play voice note"}
        className={`flex h-10 w-10 shrink-0 items-center justify-center rounded-full ${mine ? "bg-white/15" : "bg-navy-900"} ${mine ? "text-white" : "text-white"}`}>
        {playing ? (
          <svg viewBox="0 0 24 24" className="h-5 w-5 fill-current" aria-hidden="true"><rect x="6" y="5" width="4" height="14" rx="1"/><rect x="14" y="5" width="4" height="14" rx="1"/></svg>
        ) : (
          <svg viewBox="0 0 24 24" className="ml-0.5 h-5 w-5 fill-current" aria-hidden="true"><path d="M7 4.8c0-.8.9-1.3 1.6-.9l10.2 6.2a1 1 0 0 1 0 1.7L8.6 18a1 1 0 0 1-1.6-.9V4.8Z"/></svg>
        )}
      </button>
      <div className="min-w-0 flex-1">
        <button type="button" onClick={seek} aria-label="Seek within voice note" className="flex h-9 w-full items-center justify-between gap-[2px]">
          {bars.map((height, index) => (
            <span key={index} className={`w-[3px] min-w-[2px] flex-1 rounded-full ${progress >= (index + 1) / WAVEFORM_BARS ? activeBar : inactiveBar}`}
              style={{ height: `${height}px` }} />
          ))}
        </button>
        <div className={`mt-0.5 flex items-center justify-between text-[11px] tabular-nums ${muted}`}>
          <span>{formatTime(currentTime)}</span>
          <span>{duration > 0 ? formatTime(Math.max(0, duration - currentTime)) : (preview ? "Voice note" : "Voice message")}</span>
        </div>
        {playError ? <p role="alert" className={`text-[10px] ${foreground}`}>Couldn't play audio. Tap to retry.</p> : null}
      </div>
    </div>
  );
}

export function VoiceMessage({ path, mine }: { path: string; mine: boolean }) {
  const [url, setUrl] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    let active = true;
    const supabase = createBrowserSupabase();
    if (!supabase) { void Promise.resolve().then(() => { if (active) setFailed(true); }); return () => { active = false; }; }
    void supabase.storage.from(BUCKET).createSignedUrl(path, 60 * 60).then(({ data, error }) => {
      if (!active) return;
      if (error || !data?.signedUrl) setFailed(true);
      else setUrl(data.signedUrl);
    });
    return () => { active = false; };
  }, [path]);
  return url ? <VoiceWavePlayer src={url} mine={mine} /> :
    <span className={mine ? "text-sm text-white/80" : "text-sm text-grey-600"}>{failed ? "Voice note unavailable" : "Loading voice note…"}</span>;
}
