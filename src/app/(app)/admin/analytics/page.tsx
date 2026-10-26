import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ErrorState, PageTitle } from "@/components/app/states";
import { requireSession } from "@/lib/session";

export const metadata: Metadata = { title: "Analytics" };

type Daily = { date: string; newUsers: number; messages: number; conversations: number };
type Snapshot = {
  totalUsers: number; activeUsers: number; newUsers7d: number; newUsers30d: number;
  seenUsers7d: number; seenUsers30d: number; totalConversations: number;
  activeConversations: number; pendingRequests: number; conversations7d: number;
  totalMessages: number; textMessages: number; voiceMessages: number; messages7d: number;
  openReports: number; reviewingReports: number; resolvedReports: number; dismissedReports: number;
  daily: Daily[];
};

function Metric({ label, value, note }: { label: string; value: number; note?: string }) {
  return <article className="card min-w-0 p-4 sm:p-5">
    <p className="text-sm leading-snug text-grey-600">{label}</p>
    <p className="mt-2 text-2xl font-semibold tracking-tight text-navy-900 sm:text-3xl">{value.toLocaleString("en-NG")}</p>
    {note ? <p className="mt-1 text-xs text-grey-500">{note}</p> : null}
  </article>;
}

export default async function AdminAnalyticsPage() {
  const session = await requireSession();
  const { data: isAdmin } = await session.supabase.rpc("am_i_admin");
  if (!isAdmin) notFound();

  const [{ data, error }, { data: dauData, error: dauError }] = await Promise.all([
    session.supabase.rpc("admin_analytics_snapshot"),
    session.supabase.rpc("admin_daily_active_users"),
  ]);
  const stats = (data ?? null) as Snapshot | null;
  const daily = stats?.daily ?? [];
  const maxMessages = Math.max(1, ...daily.map((d) => Number(d.messages ?? 0)));

  return <>
    <p className="mb-3"><Link href="/admin" className="text-sm font-semibold text-navy-900 underline underline-offset-4">← Administration</Link></p>
    <PageTitle sub="Aggregate usage signals for One On One. No private message content is shown.">Analytics</PageTitle>
    {error || dauError || !stats ? <ErrorState what="analytics" /> : <>
      <section>
        <h2 className="mb-3 text-lg font-semibold">Users</h2>
        <div className="grid grid-cols-2 gap-3 lg:grid-cols-3">
          <Metric label="Total accounts" value={stats.totalUsers} />
          <Metric label="Active accounts" value={stats.activeUsers} note="Not suspended" />
          <Metric label="New · 7 days" value={stats.newUsers7d} />
          <Metric label="New · 30 days" value={stats.newUsers30d} />
          <Metric label="DAU · seen in 24 hours" value={Number(dauData ?? 0)} note="Presence heartbeat recorded" />
          <Metric label="WAU · seen in 7 days" value={stats.seenUsers7d} note="Presence heartbeat recorded" />
          <Metric label="MAU · seen in 30 days" value={stats.seenUsers30d} note="Presence heartbeat recorded" />
        </div>
      </section>
      <section className="mt-7">
        <h2 className="mb-3 text-lg font-semibold">Messaging</h2>
        <div className="grid grid-cols-2 gap-3 lg:grid-cols-3">
          <Metric label="Total conversations" value={stats.totalConversations} />
          <Metric label="Active conversations" value={stats.activeConversations} />
          <Metric label="Pending requests" value={stats.pendingRequests} />
          <Metric label="Conversations · 7 days" value={stats.conversations7d} />
          <Metric label="Text messages" value={stats.textMessages} />
          <Metric label="Voice messages" value={stats.voiceMessages} />
          <Metric label="All user messages" value={stats.totalMessages} />
          <Metric label="Messages · 7 days" value={stats.messages7d} />
        </div>
      </section>
      <section className="mt-7">
        <h2 className="mb-3 text-lg font-semibold">Moderation</h2>
        <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
          <Metric label="Open reports" value={stats.openReports} />
          <Metric label="Being reviewed" value={stats.reviewingReports} />
          <Metric label="Resolved" value={stats.resolvedReports} />
          <Metric label="Dismissed" value={stats.dismissedReports} />
        </div>
        <Link href="/admin" className="mt-3 inline-flex min-h-10 items-center rounded-full border border-grey-300 px-4 text-sm font-semibold">Open moderation queue</Link>
      </section>
      <section className="mt-7 card p-4 sm:p-5">
        <h2 className="text-lg font-semibold">Last 7 days</h2>
        <p className="mt-1 text-sm text-grey-600">Daily user sign-ups, messages and conversations. Message bars scale to the busiest day in this period.</p>
        <div className="mt-4 space-y-4">
          {daily.map((d) => <div key={d.date} className="grid grid-cols-[4.5rem_minmax(0,1fr)] items-center gap-3">
            <p className="text-xs text-grey-600">{new Date(d.date + "T12:00:00").toLocaleDateString("en-NG", { day: "numeric", month: "short" })}</p>
            <div className="min-w-0">
              <div className="h-2.5 overflow-hidden rounded-full bg-grey-100">
                <div className="h-full rounded-full bg-navy-900" style={{ width: Math.max(d.messages > 0 ? 2 : 0, (d.messages / maxMessages) * 100) + "%" }} />
              </div>
              <p className="mt-1 text-xs text-grey-600">{d.messages} messages · {d.conversations} conversations · {d.newUsers} new users</p>
            </div>
          </div>)}
        </div>
      </section>
      <p className="mt-4 text-xs leading-relaxed text-grey-500">These are basic product metrics, not a full retention or session-duration analysis. “Seen” is based on recorded online-presence heartbeats; it is not a guaranteed unique daily-active-user count.</p>
    </>}
  </>;
}
