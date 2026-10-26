import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { EmptyState, ErrorState, PageTitle } from "@/components/app/states";
import { requireSession } from "@/lib/session";
import { updateReportStatus } from "@/app/(app)/admin/actions";

export const metadata: Metadata = { title: "Moderation dashboard" };

type Report = {
  report_id: string;
  reporter_username: string | null;
  reporter_display_name: string | null;
  reported_user_id: string;
  reported_username: string | null;
  reported_display_name: string | null;
  reason: string;
  details: string | null;
  status: string;
  created_at: string;
};

export default async function AdminPage({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const session = await requireSession();
  const { data: isAdmin } = await session.supabase.rpc("am_i_admin");
  if (!isAdmin) notFound();

  const { data, error } = await session.supabase.rpc("admin_list_reports");
  const reports = (data ?? []) as Report[];
  const { data: isOwner } = await session.supabase.rpc("am_i_owner");
  const params = await searchParams;

  return <>
    <p className="mb-3"><Link href="/settings" className="text-sm font-semibold text-navy-900 underline underline-offset-4">← Settings</Link></p>
    <PageTitle sub="Review user reports and take moderation action.">Moderation dashboard</PageTitle>
    <div className="mb-5 flex flex-wrap gap-3">
      <Link href="/admin/analytics" className="rounded-full bg-navy-900 px-4 py-2 text-sm font-semibold text-white">Analytics</Link>
      <Link href="/admin/providers" className="rounded-full border border-grey-300 px-4 py-2 text-sm font-semibold">Provider applications</Link>
      {isOwner ? <Link href="/admin/settings" className="rounded-full border border-grey-300 px-4 py-2 text-sm font-semibold">Owner settings</Link> : null}
    </div>
    {params.error ? <p role="alert" className="mb-4 rounded-xl bg-grey-50 p-3 text-sm text-ink">That moderation action could not be completed. Refresh the queue and try again.</p> : null}
    {error ? <ErrorState what="reports" /> : reports.length === 0
      ? <EmptyState title="No reports to review" body="New user reports will appear here." />
      : <ul className="space-y-4">{reports.map((r) => <li key={r.report_id} className="card p-5">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <p className="text-xs font-bold uppercase tracking-wider text-grey-500">{r.status} · {r.reason}</p>
            <h2 className="mt-2 font-semibold">{r.reported_display_name ?? "Unknown account"}{r.reported_username ? " ( @" + r.reported_username + " )" : ""}</h2>
            <p className="mt-1 text-sm text-grey-600">Reported by {r.reporter_display_name ?? "Unknown user"}{r.reporter_username ? " ( @" + r.reporter_username + " )" : ""} · {new Date(r.created_at).toLocaleString("en-NG", { dateStyle: "medium", timeStyle: "short" })}</p>
          </div>
        </div>
        {r.details ? <p className="mt-4 whitespace-pre-wrap rounded-xl bg-grey-50 p-3 text-sm leading-relaxed">{r.details}</p> : <p className="mt-4 text-sm text-grey-500">No additional details were provided.</p>}
        <div className="mt-4 flex flex-wrap gap-2">
          {(["reviewing", "resolved", "dismissed"] as const).filter((status) => status !== r.status).map((status) => <form key={status} action={updateReportStatus}>
            <input type="hidden" name="report_id" value={r.report_id} />
            <input type="hidden" name="status" value={status} />
            <button className="min-h-10 rounded-full border border-grey-300 px-4 text-sm font-semibold hover:bg-grey-50">{status === "reviewing" ? "Mark reviewing" : status === "resolved" ? "Resolve report" : "Dismiss report"}</button>
          </form>)}
        </div>
      </li>)}</ul>}
  </>;
}
