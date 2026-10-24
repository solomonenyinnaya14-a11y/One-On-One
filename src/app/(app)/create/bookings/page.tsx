import type { Metadata } from "next";
import Link from "next/link";
import { EmptyState, ErrorState, PageTitle } from "@/components/app/states";
import { Avatar } from "@/components/ui/avatar";
import { formatNaira } from "@/lib/format";
import { requireSession } from "@/lib/session";

export const metadata: Metadata = { title: "Bookings" };

type Row = {
  id: string;
  title: string;
  kind: "text" | "voice";
  duration_minutes: number;
  provider_earnings_minor: number;
  starts_at: string;
  status: string;
  conversation_id: string | null;
  customer: { display_name: string; username: string | null; avatar_path: string | null } | null;
};

const STATUS: Record<string, string> = {
  confirmed: "Confirmed",
  in_progress: "In progress",
  completed: "Completed",
  disputed: "In dispute",
  cancelled: "Cancelled",
  refunded: "Refunded",
};

function when(iso: string) {
  return new Date(iso).toLocaleString("en-NG", { weekday: "short", day: "numeric", month: "short", hour: "numeric", minute: "2-digit", timeZone: "Africa/Lagos" });
}

export default async function IncomingBookingsPage() {
  const session = await requireSession();
  // Row-level security only returns paid, confirmed bookings to the provider.
  const { data, error } = await session.supabase
    .from("bookings")
    .select(
      "id, title, kind, duration_minutes, provider_earnings_minor, starts_at, status, conversation_id, customer:profiles!bookings_customer_id_fkey(display_name, username, avatar_path)",
    )
    .eq("provider_id", session.userId)
    .order("starts_at", { ascending: false })
    .limit(100);
  if (error) console.error("incoming bookings failed", { code: error.code, message: error.message });
  const rows = (data ?? []) as unknown as Row[];

  return (
    <>
      <p className="mb-2">
        <Link href="/create" className="text-sm font-semibold text-navy-900 underline underline-offset-4">← Create</Link>
      </p>
      <PageTitle sub="Paid, confirmed bookings from people who chose your offerings.">Bookings</PageTitle>
      {error ? (
        <ErrorState what="your bookings" />
      ) : rows.length === 0 ? (
        <EmptyState title="No bookings yet" body="When someone books and pays for one of your offerings, it shows up here." />
      ) : (
        <ul className="space-y-3">
          {rows.map((b) => (
            <li key={b.id} className="card p-4">
              <div className="flex items-center gap-3">
                <Avatar name={b.customer?.display_name ?? "Customer"} path={b.customer?.avatar_path} size="sm" />
                <div className="min-w-0 flex-1">
                  <p className="truncate font-semibold">{b.title}</p>
                  <p className="truncate text-sm text-grey-600">{b.customer?.display_name ?? "A customer"} · {when(b.starts_at)}</p>
                </div>
                <span className="shrink-0 rounded-full bg-grey-100 px-3 py-1 text-xs font-semibold">{STATUS[b.status] ?? b.status}</span>
              </div>
              <p className="mt-2 text-sm text-grey-600">
                {b.kind === "voice" ? "Voice" : "Text"} · {b.duration_minutes} min · You earn {formatNaira(b.provider_earnings_minor)}
              </p>
              {b.conversation_id ? (
                <p className="mt-3"><Link href={`/inbox/${b.conversation_id}`} className="text-sm font-semibold text-navy-900 underline underline-offset-4">Open conversation</Link></p>
              ) : null}
            </li>
          ))}
        </ul>
      )}
    </>
  );
}
