import type { Metadata } from "next";
import Link from "next/link";
import { Avatar } from "@/components/ui/avatar";
import { ErrorState, PageTitle } from "@/components/app/states";
import { requireSession } from "@/lib/session";
export const metadata: Metadata = { title: "Message requests" };
type RequestRow = { conversation_id: string; status: string; i_started: boolean; other_display_name: string; other_avatar_path: string | null; last_message_preview: string | null };
function RequestList({ rows, incoming }: { rows: RequestRow[]; incoming: boolean }) {
  if (!rows.length) return <p className="rounded-2xl border border-dashed border-grey-300 px-4 py-6 text-center text-sm text-grey-600">{incoming ? "No incoming requests right now." : "Requests you send will appear here until the other person responds."}</p>;
  return <ul className="space-y-3">{rows.map((r) => <li key={r.conversation_id}><Link href={`/inbox/${r.conversation_id}`} className="card group flex items-center gap-3 p-4 transition-all hover:-translate-y-0.5 hover:shadow-md"><Avatar name={r.other_display_name} path={r.other_avatar_path} /><span className="min-w-0 flex-1"><span className="block truncate font-semibold">{r.other_display_name}</span><span className="mt-0.5 block truncate text-sm text-grey-600">{incoming ? "Wants to start a conversation" : "Waiting for their response"}</span>{r.last_message_preview ? <span className="mt-1 block truncate text-sm">{r.last_message_preview}</span> : null}</span><span className="shrink-0 rounded-full bg-navy-50 px-3 py-1 text-xs font-semibold text-navy-900">{incoming ? "Review" : "Pending"}</span></Link></li>)}</ul>;
}
export default async function RequestsPage() {
  const session = await requireSession(), { data, error } = await session.supabase.rpc("my_inbox", { p_limit: 100, p_offset: 0 });
  const pending = ((data ?? []) as RequestRow[]).filter((r) => r.status === "request"), incoming = pending.filter((r) => !r.i_started), outgoing = pending.filter((r) => r.i_started);
  return <><PageTitle sub="You decide who can start a private chat.">Message requests</PageTitle>{error ? <ErrorState what="message requests" /> : <div className="space-y-8">
    <section aria-labelledby="incoming-requests"><div className="mb-3 flex items-baseline justify-between"><h2 id="incoming-requests" className="text-lg font-semibold">Received</h2><span className="rounded-full bg-navy-50 px-2.5 py-1 text-xs font-bold text-navy-900">{incoming.length}</span></div><RequestList rows={incoming} incoming /></section>
    <section aria-labelledby="outgoing-requests"><div className="mb-3 flex items-baseline justify-between"><h2 id="outgoing-requests" className="text-lg font-semibold">Sent</h2><span className="rounded-full bg-grey-100 px-2.5 py-1 text-xs font-bold text-grey-600">{outgoing.length}</span></div><RequestList rows={outgoing} incoming={false} /></section>
  </div>}</>;
}