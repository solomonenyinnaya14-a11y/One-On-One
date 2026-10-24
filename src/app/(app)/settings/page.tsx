import type {Metadata} from "next";
import Link from "next/link";
import {PageTitle} from "@/components/app/states";
import {BlockedUserRow} from "@/components/app/blocked-user-row";
import {requireSession} from "@/lib/session";
import {setOnlineVisibility} from "@/app/(app)/safety-actions";
export const metadata:Metadata={title:"Settings"};
type BlockRow={blocked_id:string};type Person={id:string;username:string|null;display_name:string;avatar_path:string|null};
export default async function SettingsPage(){
 const session=await requireSession();
 const {data:blocks}=await session.supabase.from("blocks").select("blocked_id").eq("blocker_id",session.userId).order("created_at",{ascending:false});
 const ids=((blocks??[]) as BlockRow[]).map(x=>x.blocked_id);
 const {data:people}=ids.length?await session.supabase.from("profiles").select("id,username,display_name,avatar_path").in("id",ids):{data:[] as Person[]};
 const byId=new Map(((people??[]) as Person[]).map(p=>[p.id,p]));
 const {data:privacy}=await session.supabase.from("profiles").select("show_online_status").eq("id",session.userId).maybeSingle();
 return <><p className="mb-3"><Link href="/me" className="text-sm font-semibold text-navy-900 underline underline-offset-4">← Profile</Link></p><PageTitle sub="Manage your privacy and who can contact you.">Settings</PageTitle>
 <section className="card p-5"><h2 className="text-lg font-semibold">Privacy</h2><p className="mt-1 text-sm leading-relaxed text-grey-600">Choose whether people can see when you are online. Your last-seen status is not shown when this is turned off.</p><form action={setOnlineVisibility} className="mt-4 flex items-center justify-between gap-4"><label htmlFor="show_online_status" className="font-medium">Show online status</label><input id="show_online_status" name="show_online_status" type="checkbox" defaultChecked={privacy?.show_online_status??true} className="h-6 w-6 accent-navy-900"/><button className="min-h-10 rounded-full bg-navy-900 px-5 text-sm font-semibold text-white">Save</button></form></section>
 <section className="mt-7"><h2 className="text-lg font-semibold">Blocked accounts</h2><p className="mt-1 mb-4 text-sm text-grey-600">Blocked people can no longer start conversations with you. You can unblock them at any time.</p>{ids.length===0?<p className="rounded-2xl border border-dashed border-grey-300 p-5 text-center text-sm text-grey-600">You haven&apos;t blocked anyone.</p>:<ul className="space-y-3">{ids.map(id=>{const p=byId.get(id);return p?<BlockedUserRow key={id} id={id} name={p.display_name} username={p.username} avatarPath={p.avatar_path}/>:null;})}</ul>}</section>
 <section className="mt-7 rounded-2xl bg-grey-50 p-5"><h2 className="font-semibold">Need help?</h2><p className="mt-1 text-sm leading-relaxed text-grey-600">Use Report user on a person&apos;s profile or inside a chat to flag spam, harassment, impersonation, scams, or other concerns.</p></section></>;
}