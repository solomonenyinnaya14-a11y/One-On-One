import type { Metadata } from "next";
import Link from "next/link";
import { EmptyState, ErrorState, PageTitle } from "@/components/app/states";
import { Avatar } from "@/components/ui/avatar";
import { requireSession } from "@/lib/session";

export const metadata: Metadata = { title: "Inbox" };

type InboxRow = {
  conversation_id: string;
  status: string;
  i_started: boolean;
  other_username: string | null;
  other_display_name: string;
  other_avatar_path: string | null;
  last_message_preview: string | null;
  unread_count: number | string;
};

export default async function InboxPage() {
  const session = await requireSession();
  const { data, error } = await session.supabase.rpc("my_inbox", { p_limit: 50, p_offset: 0 });
  const rows = (data ?? []) as InboxRow[];

  return (
    <>
      <PageTitle>Inbox</PageTitle>
      {error ? (
        <ErrorState what="your conversations" />
      ) : rows.length === 0 ? (
        <EmptyState title="No conversations yet" body="When you message someone, or someone messages you, it shows up here." action={{ href: "/discover", label: "Find someone to talk to" }} />
      ) : (
        <ul className="space-y-3">
          {rows.map((r) => (
            <li key={r.conversation_id}>
              <Link
                href={`/inbox/${r.conversation_id}`}
                className="flex items-center gap-4 card p-4 hover:shadow-md"
              >
                <Avatar name={r.other_display_name} path={r.other_avatar_path} />
                <div className="min-w-0 flex-1">
                  <p className="truncate font-semibold">{r.other_display_name}</p>
                  <p className="truncate text-sm text-grey-600">
                    {r.status === "request" ? (r.i_started ? "Request sent · " : "Request · ") : ""}
                    {r.last_message_preview}
                  </p>
                </div>
                {Number(r.unread_count) > 0 ? (
                  <span aria-label={`${r.unread_count} unread`} className="rounded-full bg-navy-900 px-2 text-xs font-semibold leading-6 text-white">
                    {r.unread_count}
                  </span>
                ) : null}
              </Link>
            </li>
          ))}
        </ul>
      )}
    </>
  );
}
