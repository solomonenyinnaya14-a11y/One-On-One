import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { Chat, type ChatMessage } from "@/components/app/chat";
import { Avatar } from "@/components/ui/avatar";
import { OnlineStatus } from "@/components/app/presence";
import { SafetyControls } from "@/components/app/safety-controls";
import { requireSession } from "@/lib/session";

export const metadata: Metadata = { title: "Conversation" };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export default async function ConversationPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!UUID.test(id)) notFound();
  const session = await requireSession();

  // Row-level security means this only returns conversations the person is in.
  const { data: convo } = await session.supabase
    .from("conversations")
    .select("id, user_a, user_b, initiator_id, status")
    .eq("id", id)
    .maybeSingle();
  if (!convo) notFound();

  const otherId = convo.user_a === session.userId ? convo.user_b : convo.user_a;
  const { data: myBlock } = await session.supabase.from("blocks").select("blocked_id").eq("blocker_id", session.userId).eq("blocked_id", otherId).maybeSingle();
  const [profileResult, { data: rows, error }] = await Promise.all([
    session.supabase
      .from("profiles")
      .select("id, username, display_name, avatar_path, status, last_seen_at, show_online_status")
      .eq("id", otherId)
      .maybeSingle(),
    session.supabase
      .from("messages")
      .select("id, sender_id, kind, body, created_at")
      .eq("conversation_id", id)
      .order("created_at", { ascending: false })
      .limit(200),
  ]);

  // Presence columns are optional until the presence migration is applied.
  // If they are missing, the whole profile query fails; that previously made
  // an existing participant look unavailable even when their account was active.
  let other: {
    id: string;
    username: string | null;
    display_name: string;
    avatar_path: string | null;
    status: string;
    last_seen_at: string | null;
    show_online_status: boolean;
  } | null = profileResult.data
    ? {
        ...profileResult.data,
        last_seen_at: profileResult.data.last_seen_at ?? null,
        show_online_status: profileResult.data.show_online_status ?? true,
      }
    : null;

  const profileError = profileResult.error;
  const missingPresenceColumns =
    profileError?.code === "42703" ||
    (Boolean(profileError?.message.includes("column")) &&
      Boolean(
        profileError?.message.includes("last_seen_at") ||
          profileError?.message.includes("show_online_status"),
      ));

  if (missingPresenceColumns) {
    const { data: coreProfile, error: coreProfileError } = await session.supabase
      .from("profiles")
      .select("id, username, display_name, avatar_path, status")
      .eq("id", otherId)
      .maybeSingle();

    other = !coreProfile || coreProfileError
      ? null
      : { ...coreProfile, last_seen_at: null, show_online_status: true };
  }

  const messages = ((rows ?? []) as ChatMessage[]).reverse();
  const { data: peerReadAt } = await session.supabase.rpc("conversation_peer_read_at", { p_conversation: id });
  await session.supabase.rpc("mark_conversation_read", { p_conversation: id });

  return (
    <div className="flex min-h-[calc(100dvh-10rem)] flex-col">
      <header className="mb-4 flex items-center gap-3 border-b border-grey-200 pb-4">
        <Link href="/inbox" aria-label="Back to Inbox" className="inline-flex min-h-11 min-w-11 items-center justify-center text-2xl">
          ←
        </Link>
        <Avatar name={other?.display_name ?? "Unknown"} path={other?.avatar_path ?? null} />
        <div className="min-w-0">
          {other?.username ? (
            <Link href={`/u/${other.username}`} className="block truncate font-semibold">
              {other.display_name}
            </Link>
          ) : (
            <p className="truncate font-semibold">{other?.display_name ?? "Unavailable"}</p>
          )}
          {other?.username ? <p className="truncate text-sm text-grey-600">@{other.username}</p> : null}
          <OnlineStatus targetId={otherId} lastSeenAt={other?.last_seen_at} showStatus={other?.show_online_status ?? true} className="mt-1" />
        </div>
      </header>
      <Chat
        conversationId={id}
        me={session.userId}
        status={convo.status}
        iStarted={convo.initiator_id === session.userId}
        canSend={other?.status === "active" && !myBlock}
        initial={messages}
        loadError={Boolean(error)}
        otherName={other?.display_name ?? "Unavailable"}
        otherAvatarPath={other?.avatar_path ?? null}
        initialPeerReadAt={typeof peerReadAt === "string" ? peerReadAt : null}
      />
      {other ? <SafetyControls targetId={otherId} targetName={other.display_name} /> : null}
    </div>
  );
}
