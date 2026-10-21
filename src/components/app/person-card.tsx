import Link from "next/link";
import { Avatar } from "@/components/ui/avatar";
import type { PersonCard } from "@/lib/queries";

export function PersonListItem({ person }: { person: PersonCard }) {
  const rating =
    person.provider && person.provider.rating_count > 0
      ? (person.provider.rating_sum / person.provider.rating_count).toFixed(1)
      : null;
  return (
    <li>
      <Link
        href={`/u/${person.username}`}
        className="flex items-center gap-4 rounded-2xl border border-grey-200 bg-paper p-4 transition-colors hover:bg-grey-50"
      >
        <Avatar name={person.display_name} path={person.avatar_path} />
        <span className="min-w-0 flex-1">
          <span className="flex items-center gap-2">
            <span className="truncate font-semibold text-ink">{person.display_name}</span>
            {person.provider ? (
              <span className="shrink-0 rounded-full bg-navy-900 px-2 py-0.5 text-xs font-semibold text-white">
                Provider
              </span>
            ) : null}
          </span>
          <span className="block truncate text-sm text-grey-600">@{person.username}</span>
          {person.provider?.headline || person.bio ? (
            <span className="mt-1 line-clamp-2 block text-sm text-ink">
              {person.provider?.headline ?? person.bio}
            </span>
          ) : null}
          {rating ? (
            <span className="mt-1 block text-xs font-semibold text-grey-600">
              {rating} · {person.provider?.rating_count} reviews
            </span>
          ) : null}
        </span>
      </Link>
    </li>
  );
}
