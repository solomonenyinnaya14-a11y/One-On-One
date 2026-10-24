import { Avatar } from "@/components/ui/avatar";
import { OnlineStatus } from "@/components/app/presence";
export type ProfileViewPerson = { display_name: string; username: string | null; avatar_path: string | null; bio: string | null; expertise: string | null; interests: string[]; id?: string; last_seen_at?: string | null; show_online_status?: boolean; };
type Props = { person: ProfileViewPerson; isSelf?: boolean; email?: string | null; actions?: React.ReactNode };
export function ProfileView({ person, isSelf = false, email, actions }: Props) {
  return <article>
    <header className="card overflow-hidden"><div className="h-24 bg-gradient-to-r from-navy-950 via-navy-800 to-navy-700" aria-hidden="true" /><div className="-mt-10 px-5 pb-6 sm:px-7">
      <div className="flex items-end gap-4"><span className="rounded-full border-4 border-white bg-white"><Avatar name={person.display_name} path={person.avatar_path} size="lg" /></span><div className="min-w-0 flex-1 pb-1"><h1 className="truncate font-serif text-2xl font-medium leading-tight sm:text-3xl">{person.display_name}</h1><p className="truncate text-sm text-grey-600">@{person.username}</p><OnlineStatus targetId={person.id} lastSeenAt={person.last_seen_at} showStatus={person.show_online_status ?? true} className="mt-1" /></div></div>
      {email && isSelf ? <p className="mt-3 truncate text-sm text-grey-600">{email}</p> : null}
      {person.bio ? <p className="mt-5 whitespace-pre-line leading-relaxed">{person.bio}</p> : null}
      {person.expertise ? <p className="mt-4 text-sm text-grey-600"><span className="font-semibold text-ink">Knows about:</span> {person.expertise}</p> : null}
      {person.interests.length ? <ul className="mt-4 flex flex-wrap gap-2" aria-label="Interests">{person.interests.map((interest) => <li key={interest} className="rounded-full bg-navy-50 px-3 py-1 text-sm font-medium text-navy-900">{interest}</li>)}</ul> : null}
    </div></header>
    {actions ? <section className="mt-5 rounded-2xl border border-grey-200 bg-white p-5">{actions}{!isSelf ? <p className="mt-3 text-sm leading-relaxed text-grey-600">Your first message is a request. This person can accept or decline before the private chat opens.</p> : null}</section> : null}
    {isSelf ? <p className="mt-5 rounded-2xl bg-grey-50 px-4 py-3 text-sm text-grey-600">Your profile helps people recognize you before they accept a message request.</p> : null}
  </article>;
}