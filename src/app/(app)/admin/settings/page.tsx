import type {Metadata} from "next";
import Link from "next/link";
import {notFound} from "next/navigation";
import {PageTitle} from "@/components/app/states";
import {requireSession} from "@/lib/session";
import {grantAdministrator,revokeAdministrator} from "@/app/(app)/admin/actions";
export const metadata:Metadata={title:"Owner admin settings"};
type AdminRow={user_id:string;username:string|null;display_name:string;is_owner:boolean};
type UserRow={user_id:string;username:string|null;display_name:string;is_admin:boolean};
export default async function OwnerAdminSettingsPage({searchParams}:{searchParams:Promise<{q?:string;error?:string;updated?:string}>}){
 const session=await requireSession();
 const {data:isOwner}=await session.supabase.rpc("am_i_owner");
 if(!isOwner)notFound();
 const params=await searchParams; const query=(params.q??"").trim();
 const {data:adminData}=await session.supabase.rpc("owner_list_admins");
 const admins=(adminData??[]) as AdminRow[];
 const {data:usersData}=query.length>=2?await session.supabase.rpc("owner_search_users",{p_query:query}):{data:[] as UserRow[]};
 const users=(usersData??[]) as UserRow[];
 return <><p className="mb-3"><Link href="/settings" className="text-sm font-semibold text-navy-900 underline underline-offset-4">← Settings</Link></p><PageTitle sub="Only the platform owner can grant or remove administrator access.">Owner admin settings</PageTitle>
 <section className="card p-5"><h2 className="text-lg font-semibold">Administrators</h2><p className="mt-1 text-sm text-grey-600">The owner account cannot be removed here. Additional administrators use their own accounts; never share your sign-in.</p>{admins.length===0?<p className="mt-4 text-sm text-grey-600">No administrator accounts found.</p>:<ul className="mt-4 divide-y divide-grey-200">{admins.map(a=><li key={a.user_id} className="flex items-center justify-between gap-3 py-3"><div className="min-w-0"><p className="truncate font-semibold">{a.display_name}</p><p className="truncate text-sm text-grey-600">{a.username?"@"+a.username:"No username"}{a.is_owner?" · Owner":" · Administrator"}</p></div>{!a.is_owner?<form action={revokeAdministrator}><input type="hidden" name="user_id" value={a.user_id}/><button className="min-h-10 rounded-full border border-grey-300 px-4 text-sm font-semibold">Remove</button></form>:null}</li>)}</ul>}</section>
 <section className="mt-6 card p-5"><h2 className="text-lg font-semibold">Grant administrator access</h2><p className="mt-1 text-sm text-grey-600">Search by username or display name. Confirm the correct account before granting access.</p><form className="mt-4 flex gap-2" method="get"><input name="q" defaultValue={query} minLength={2} placeholder="Search username or name" className="min-h-12 min-w-0 flex-1 rounded-xl border border-grey-300 px-4" aria-label="Search users"/><button className="min-h-12 rounded-xl bg-navy-900 px-5 font-semibold text-white">Search</button></form>{query.length>=2?<ul className="mt-4 divide-y divide-grey-200">{users.map(u=><li key={u.user_id} className="flex items-center justify-between gap-3 py-3"><div className="min-w-0"><p className="truncate font-semibold">{u.display_name}</p><p className="truncate text-sm text-grey-600">{u.username?"@"+u.username:"No username"}{u.is_admin?" · Already an administrator":""}</p></div>{u.is_admin?null:<form action={grantAdministrator}><input type="hidden" name="user_id" value={u.user_id}/><button className="min-h-10 rounded-full bg-navy-900 px-4 text-sm font-semibold text-white">Make admin</button></form>}</li>)}{users.length===0?<li className="py-4 text-sm text-grey-600">No matching users found.</li>:null}</ul>:null}</section>
 {params.error?<p role="alert" className="mt-4 rounded-xl bg-grey-50 p-3 text-sm text-ink">That admin change could not be completed. Refresh and try again.</p>:null}{params.updated?<p role="status" className="mt-4 rounded-xl bg-grey-50 p-3 text-sm text-ink">Administrator settings updated.</p>:null}
 </>;
}
