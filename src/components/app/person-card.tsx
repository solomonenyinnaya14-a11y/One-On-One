import Link from "next/link";
import { Avatar } from "@/components/ui/avatar";
import { formatNaira } from "@/lib/format";
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
        className="card flex items-center gap-4 p-4 transition-shadow hover:shadow-md"
      >
        <Avatar name={person.display_name} path={person.avatar_path} />
        <span className="min-w-0 flex-1">
          <span className="flex items-center gap-2">
            <span className="truncate font-semibold text-ink">{person.display_name}</span>
            {person.provider ? (
              <span className="shrink-0 rounded-full bg-navy-50 px-2 py-0.5 text-xs font-semibold text-navy-900">
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
          {person.offerings.length > 0 ? (
            <span className="mt-2 block text-sm font-semibold text-navy-900">
              {person.offerings[0].kind === "voice" ? "Voice" : "Text"} · {person.offerings[0].duration_minutes} min · {formatNaira(person.offerings[0].price_minor)}
              {person.offerings.length > 1 ? ` · +${person.offerings.length - 1} more` : ""}
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
