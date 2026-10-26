"use client";

import { useEffect, useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { markConversationRead, respondToRequest, sendMessage } from "@/app/(app)/actions";
import { refreshPeerReadAt } from "@/app/(app)/safety-actions";
import { Avatar } from "@/components/ui/avatar";
import { createBrowserSupabase } from "@/lib/supabase/browser";
import { VoiceMessage, VoiceRecorder } from "@/components/app/voice-message";

export type ChatMessage = {
  id: string;
  sender_id: string | null;
  kind: string;
  body: string | null;
  created_at: string;
};

type Props = {
  conversationId: string;
  me: string;
  status: string;
  iStarted: boolean;
  canSend: boolean;
  initial: ChatMessage[];
  loadError: boolean;
  otherName: string;
  otherAvatarPath: string | null;
  initialPeerReadAt: string | null;
};

function timeLabel(iso: string) {
  return new Date(iso).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
}

export function Chat({ conversationId, me, status: initialStatus, iStarted, canSend, initial, loadError, otherName, otherAvatarPath, initialPeerReadAt }: Props) {
  const router = useRouter();
  const [messages, setMessages] = useState<ChatMessage[]>(initial);
  const [status, setStatus] = useState(initialStatus);
  const [draft, setDraft] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [sending, startSend] = useTransition();
  const [answering, startAnswer] = useTransition();
  const [live, setLive] = useState<"connecting" | "live" | "offline">("connecting");
  const [peerReadAt, setPeerReadAt] = useState<string | null>(initialPeerReadAt);
  const bottom = useRef<HTMLDivElement>(null);

  function add(m: ChatMessage) {
    setMessages((prev) => (prev.some((p) => p.id === m.id) ? prev : [...prev, m]));
  }

  useEffect(() => {
    let active = true;
    // Opening the conversation marks incoming messages as read. Refreshing the
    // server-rendered inbox data keeps its unread badge in sync when navigating back.
    void (async () => {
      await markConversationRead(conversationId);
      if (active) router.refresh();
    })();
    const pollReadStatus = async () => { const value = await refreshPeerReadAt(conversationId); if (active) setPeerReadAt(value); };
    void pollReadStatus();
    const readTimer = window.setInterval(() => { void pollReadStatus(); }, 10000);
    const supabase = createBrowserSupabase();
    if (!supabase) return () => { active = false; window.clearInterval(readTimer); };
    const channel = supabase
      .channel(`conversation:${conversationId}`)
      .on(
        "postgres_changes",
        { event: "INSERT", schema: "public", table: "messages", filter: `conversation_id=eq.${conversationId}` },
        (payload) => {
          const m = payload.new as ChatMessage;
          add(m);
          if (m.sender_id !== me) void markConversationRead(conversationId);
        },
      )
      .on(
        "postgres_changes",
        { event: "UPDATE", schema: "public", table: "conversations", filter: `id=eq.${conversationId}` },
        (payload) => setStatus((payload.new as { status: string }).status),
      )
      .subscribe((s) => setLive(s === "SUBSCRIBED" ? "live" : s === "CLOSED" || s === "CHANNEL_ERROR" ? "offline" : "connecting"));
    return () => {
      active = false;
      window.clearInterval(readTimer);
      void supabase.removeChannel(channel);
    };
  }, [conversationId, me]);

  useEffect(() => {
    bottom.current?.scrollIntoView({ block: "end" });
  }, [messages.length]);

  function submit(e: React.FormEvent) {
    e.preventDefault();
    const body = draft.trim();
    if (!body || sending) return;
    setError(null);
    startSend(async () => {
      const r = await sendMessage(conversationId, body);
      if (r.error || !r.id) {
        setError(r.error ?? "Your message wasn't sent. Please try again.");
        return; // keep the draft so nothing is lost
      }
      setDraft("");
      add({ id: r.id, sender_id: me, kind: "user", body, created_at: new Date().toISOString() });
    });
  }

  const awaitingMyAnswer = status === "request" && !iStarted;
  const declined = status === "declined";
  const blockedReason = !canSend
    ? "This person is no longer available."
    : declined
      ? iStarted
        ? "This person declined your message request."
        : "You declined this request."
      : null;

  return (
    <>
      {loadError ? (
        <p role="alert" className="mb-3 rounded-xl border-2 border-ink p-3 text-sm font-semibold">
          We couldn&apos;t load all messages. Refresh to try again.
        </p>
      ) : null}

      <div className="flex-1 space-y-2 overflow-y-auto pb-4" role="log" aria-live="polite" aria-label="Messages">
        {messages.length === 0 ? (
          <p className="py-10 text-center text-sm text-grey-600">No messages yet. Say hello.</p>
        ) : (
          messages.map((m) => {
            if (m.kind !== "user" && m.kind !== "voice") {
              return (
                <p key={m.id} className="py-1 text-center text-xs text-grey-600">
                  {m.body ?? "Booking update"}
                </p>
              );
            }
            const mine = m.sender_id === me;
            return (
              <div key={m.id} className={`flex items-end gap-2 ${mine ? "justify-end" : "justify-start"}`}>
                {mine ? null : <Avatar name={otherName} path={otherAvatarPath} size="xs" />}
                <div
                  className={`max-w-[80%] rounded-2xl px-4 py-2 ${
                    mine ? "rounded-br-md bg-navy-900 text-white" : "rounded-bl-md border border-grey-200 bg-white text-ink"
                  }`}
                >
                  {m.kind === "voice" ? <VoiceMessage path={m.body ?? ""} mine={mine} /> : <p className="whitespace-pre-wrap break-words">{m.body}</p>}
                  <p className={`mt-1 text-[11px] ${mine ? "text-white/70" : "text-grey-600"}`}>
                    {mine ? "You" : otherName.split(" ")[0]} · {timeLabel(m.created_at)}{mine ? <span className={peerReadAt && new Date(peerReadAt).getTime() >= new Date(m.created_at).getTime() ? "ml-2 font-semibold text-sky-300" : "ml-2 text-white/60"} aria-label={peerReadAt && new Date(peerReadAt).getTime() >= new Date(m.created_at).getTime() ? "Read" : "Sent"}>{peerReadAt && new Date(peerReadAt).getTime() >= new Date(m.created_at).getTime() ? "✓✓" : "✓"}</span> : null}
                  </p>
                </div>
              </div>
            );
          })
        )}
        <div ref={bottom} />
      </div>

      {awaitingMyAnswer ? (
        <div className="card mb-3 border-ink/30 p-4">
          <p className="font-semibold">Message request</p>
          <p className="mt-1 text-sm text-grey-600">
            This person isn&apos;t in your conversations yet. Accept to keep talking, or decline.
          </p>
          <div className="mt-3 flex gap-3">
            <button
              type="button"
              disabled={answering}
              onClick={() =>
                startAnswer(async () => {
                  const r = await respondToRequest(conversationId, true);
                  if (r.error) setError(r.error);
                  else setStatus("active");
                })
              }
              className="min-h-11 rounded-full bg-navy-900 px-6 text-sm font-semibold text-white disabled:opacity-60"
            >
              Accept
            </button>
            <button
              type="button"
              disabled={answering}
              onClick={() =>
                startAnswer(async () => {
                  const r = await respondToRequest(conversationId, false);
                  if (r.error) setError(r.error);
                  else setStatus("declined");
                })
              }
              className="min-h-11 rounded-full border-2 border-ink px-6 text-sm font-semibold disabled:opacity-60"
            >
              Decline
            </button>
          </div>
        </div>
      ) : null}

      {error ? (
        <p role="alert" className="mb-2 text-sm font-semibold">
          {error}
        </p>
      ) : null}

      {blockedReason ? (
        <p className="rounded-xl bg-grey-100 p-3 text-center text-sm">{blockedReason}</p>
      ) : (
        <form onSubmit={submit} className="flex items-end gap-2">
          <label htmlFor="message" className="sr-only">
            Message
          </label>
          <textarea
            id="message"
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" && !e.shiftKey && !e.nativeEvent.isComposing) {
                e.preventDefault();
                e.currentTarget.form?.requestSubmit();
              }
            }}
            rows={1}
            maxLength={4000}
            placeholder="Write a message"
            className="max-h-32 min-h-12 flex-1 resize-none rounded-2xl border-2 border-grey-300 px-4 py-3 focus:border-navy-900 focus:outline-none"
          />
          <VoiceRecorder conversationId={conversationId} userId={me} disabled={sending || answering || Boolean(blockedReason)} onSent={(id, path) => { add({ id, sender_id: me, kind: "voice", body: path, created_at: new Date().toISOString() }); router.refresh(); }} />
          <button
            type="submit"
            disabled={sending || draft.trim().length === 0}
            className="min-h-12 rounded-full bg-navy-900 px-6 font-semibold text-white disabled:opacity-50"
          >
            {sending ? "…" : "Send"}
          </button>
        </form>
      )}
      <p className="mt-2 text-center text-[11px] text-grey-600" aria-live="off">
        {live === "live" ? "Live" : live === "offline" ? "Reconnecting… new messages appear after a refresh" : ""}
      </p>
    </>
  );
}
