import type { Metadata } from "next";
import Link from "next/link";
import { EmptyState, ErrorState, PageTitle } from "@/components/app/states";
import { Avatar } from "@/components/ui/avatar";
import { requireSession } from "@/lib/session";
import { InboxRefresh } from "@/components/app/inbox-refresh";
export const metadata: Metadata = { title: "Messages" };
type InboxRow = { conversation_id: string; status: string; other_display_name: string; other_avatar_path: string | null; last_message_preview: string | null; unread_count: number | string };
export default async function InboxPage() {
  const session = await requireSession(), { data, error } = await session.supabase.rpc("my_inbox", { p_limit: 100, p_offset: 0 });
  const rows = ((data ?? []) as InboxRow[]).filter((r) => r.status === "active");
  return <><InboxRefresh /><PageTitle sub="Your accepted conversations, all in one place.">Messages</PageTitle>{error ? <ErrorState what="your messages" /> : !rows.length ? <EmptyState title="Your conversations start here" body="When someone accepts a message request, your private chat will appear here." action={{ href: "/discover", label: "Discover people" }} /> : <ul className="space-y-3">{rows.map((r) => <li key={r.conversation_id}><Link href={`/inbox/${r.conversation_id}`} className="card flex items-center gap-4 p-4 transition-all hover:-translate-y-0.5 hover:shadow-md"><Avatar name={r.other_display_name} path={r.other_avatar_path} /><div className="min-w-0 flex-1"><p className="truncate font-semibold">{r.other_display_name}</p><p className="truncate text-sm text-grey-600">{r.last_message_preview || "Start a conversation"}</p></div>{Number(r.unread_count)>0 ? <span aria-label={`${r.unread_count} unread`} className="rounded-full bg-navy-900 px-2.5 text-xs font-semibold leading-6 text-white">{Number(r.unread_count)>99 ? "99+" : r.unread_count}</span> : <span aria-hidden="true" className="text-xl text-grey-300">›</span>}</Link></li>)}</ul>}<p className="mt-6 text-center text-sm text-grey-600">Waiting on a request? <Link href="/requests" className="font-semibold text-navy-900 underline underline-offset-4">View message requests</Link></p></>;
}