"use client";

import { useEffect, useRef, useState } from "react";
import { sendVoiceMessage } from "@/app/(app)/actions";
import { createBrowserSupabase } from "@/lib/supabase/browser";

const BUCKET = "voice-messages";
const MAX_SECONDS = 60;
const MAX_BYTES = 10 * 1024 * 1024;

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
  const [recording, setRecording] = useState(false);
  const [busy, setBusy] = useState(false);
  const [seconds, setSeconds] = useState(0);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => () => {
    if (timeout.current !== null) window.clearTimeout(timeout.current);
    stream.current?.getTracks().forEach((track) => track.stop());
  }, []);

  async function start() {
    setError(null);
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
      const rec = new MediaRecorder(media, { mimeType });
      recorder.current = rec;
      rec.ondataavailable = (event) => { if (event.data.size > 0) chunks.current.push(event.data); };
      rec.onerror = () => {
        setError("Recording stopped unexpectedly. Please try again.");
        setRecording(false);
        media.getTracks().forEach((track) => track.stop());
      };
      rec.onstop = async () => {
        media.getTracks().forEach((track) => track.stop());
        stream.current = null;
        setRecording(false);
        setSeconds(0);
        const blob = new Blob(chunks.current, { type: mimeType });
        if (blob.size === 0) return;
        if (blob.size > MAX_BYTES) {
          setError("That voice note is too large. Try recording a shorter note.");
          return;
        }
        const supabase = createBrowserSupabase();
        if (!supabase) {
          setError("Audio storage isn't configured yet.");
          return;
        }
        setBusy(true);
        try {
          const { ext, contentType } = fileExtension(mimeType);
          const path = `${conversationId}/${userId}/${crypto.randomUUID()}.${ext}`;
          const { error: uploadError } = await supabase.storage.from(BUCKET).upload(path, blob, {
            contentType,
            cacheControl: "3600",
            upsert: false,
          });
          if (uploadError) throw uploadError;
          const result = await sendVoiceMessage(conversationId, path);
          if (result.error || !result.id) {
            setError(result.error ?? "Your voice note wasn't sent. Please try again.");
            return;
          }
          onSent(result.id, path);
        } catch {
          setError("Your voice note wasn't sent. Check your connection and try again.");
        } finally {
          setBusy(false);
        }
      };
      rec.start(250);
      setRecording(true);
      setSeconds(0);
      const startedAt = Date.now();
      const tick = () => {
        const elapsed = Math.min(MAX_SECONDS, Math.floor((Date.now() - startedAt) / 1000));
        setSeconds(elapsed);
        if (elapsed >= MAX_SECONDS) {
          if (rec.state !== "inactive") rec.stop();
        } else if (rec.state !== "inactive") {
          timeout.current = window.setTimeout(tick, 250);
        }
      };
      timeout.current = window.setTimeout(tick, 250);
    } catch {
      setError("Allow microphone access to record a voice note.");
      stream.current?.getTracks().forEach((track) => track.stop());
      stream.current = null;
    }
  }

  function stop() {
    if (timeout.current !== null) window.clearTimeout(timeout.current);
    if (recorder.current?.state === "recording") recorder.current.stop();
  }

  return <div className="flex flex-col items-end gap-1">
    <button type="button" onClick={recording ? stop : () => void start()} disabled={disabled || busy}
      aria-label={recording ? "Stop voice recording" : "Record a voice message"}
      className="min-h-12 min-w-12 rounded-full border-2 border-navy-900 px-3 text-sm font-semibold disabled:opacity-50">
      {busy ? "Sending…" : recording ? `Stop ${seconds}s` : "Voice"}
    </button>
    {error ? <p role="alert" className="max-w-56 text-right text-xs font-medium text-red-700">{error}</p> : null}
  </div>;
}

export function VoiceMessage({ path, mine }: { path: string; mine: boolean }) {
  const [url, setUrl] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    let active = true;
    const supabase = createBrowserSupabase();
    if (!supabase) { setFailed(true); return; }
    void supabase.storage.from(BUCKET).createSignedUrl(path, 60 * 60).then(({ data, error }) => {
      if (!active) return;
      if (error || !data?.signedUrl) setFailed(true);
      else setUrl(data.signedUrl);
    });
    return () => { active = false; };
  }, [path]);
  return url ? <audio controls preload="none" src={url} className="max-w-full" aria-label="Voice message" /> :
    <span className={mine ? "text-sm text-white/80" : "text-sm text-grey-600"}>{failed ? "Voice note unavailable" : "Loading voice note…"}</span>;
}
