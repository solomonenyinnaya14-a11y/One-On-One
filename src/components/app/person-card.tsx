import Link from "next/link";
import { Avatar } from "@/components/ui/avatar";
import type { PersonCard } from "@/lib/queries";
export function PersonListItem({ person }: { person: PersonCard }) {
  return <li><Link href={`/u/${person.username}`} className="group card flex items-center gap-4 p-4 transition-all duration-200 hover:-translate-y-0.5 hover:shadow-md focus-visible:ring-2 focus-visible:ring-navy-700">
    <Avatar name={person.display_name} path={person.avatar_path} />
    <span className="min-w-0 flex-1"><span className="block truncate font-semibold text-ink">{person.display_name}</span><span className="mt-0.5 block truncate text-sm text-grey-600">@{person.username}</span>
      {person.bio ? <span className="mt-2 line-clamp-2 block text-sm leading-relaxed text-grey-600">{person.bio}</span> : person.interests.length ? <span className="mt-2 block truncate text-sm text-grey-600">{person.interests.slice(0,3).join(" · ")}</span> : null}
    </span><span aria-hidden="true" className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-navy-50 text-navy-900 transition-colors group-hover:bg-navy-900 group-hover:text-white"><svg viewBox="0 0 24 24" className="h-4 w-4" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M5 12h14M13 6l6 6-6 6" /></svg></span>
  </Link></li>;
}