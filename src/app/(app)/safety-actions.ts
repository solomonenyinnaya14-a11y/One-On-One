"use server";
import { revalidatePath } from "next/cache";
import { getSession } from "@/lib/session";
const reasons = new Set(["spam","harassment","impersonation","inappropriate","scam","other"]);
export async function blockUser(targetId: string): Promise<{error?: string; success?: boolean}> {
 const session=await getSession(); if(!session)return {error:"Please sign in again."};
 if(!targetId||targetId===session.userId)return {error:"You can't block this account."};
 const {error}=await session.supabase.from("blocks").insert({blocker_id:session.userId,blocked_id:targetId});
 if(error&&error.code!=="23505")return {error:"We couldn't block this person. Please try again."};
 revalidatePath("/discover");revalidatePath("/requests");revalidatePath("/inbox");revalidatePath("/settings");return {success:true};
}
export async function unblockUser(targetId:string):Promise<{error?:string;success?:boolean}> {
 const session=await getSession();if(!session)return {error:"Please sign in again."};
 const {error}=await session.supabase.from("blocks").delete().eq("blocker_id",session.userId).eq("blocked_id",targetId);
 if(error)return {error:"We couldn't unblock this person. Please try again."};
 revalidatePath("/settings");revalidatePath("/discover");return {success:true};
}
export async function reportUser(targetId:string,reason:string,details:string):Promise<{error?:string;success?:boolean}> {
 const session=await getSession();if(!session)return {error:"Please sign in again."};
 if(!reasons.has(reason))return {error:"Choose a report reason."};
 if(details.trim().length>1000)return {error:"Please keep the details under 1,000 characters."};
 const {error}=await session.supabase.rpc("report_user",{p_reported_user:targetId,p_reason:reason,p_details:details.trim()||null});
 if(error){if(error.code==="54000")return {error:"You've reached today's report limit. Please try again later."};return {error:"We couldn't submit this report. Please try again."};}
 return {success:true};
}
export async function updatePresence():Promise<void>{const session=await getSession();if(session&&session.profile.status==="active")await session.supabase.rpc("heartbeat_presence");}
export async function getPresence(targetId:string):Promise<string|null>{
 const session=await getSession();if(!session||!targetId)return null;
 const {data}=await session.supabase.from("profiles").select("last_seen_at,show_online_status").eq("id",targetId).maybeSingle();
 return data?.show_online_status&&typeof data.last_seen_at==="string"?data.last_seen_at:null;
}
export async function setOnlineVisibility(formData:FormData):Promise<void>{
 const session=await getSession();if(!session)return;
 const enabled=formData.get("show_online_status")==="on";
 await session.supabase.from("profiles").update({show_online_status:enabled}).eq("id",session.userId);
 await session.supabase.rpc("heartbeat_presence");
 revalidatePath("/settings");revalidatePath("/me");revalidatePath("/inbox");revalidatePath("/discover");
}
export async function refreshPeerReadAt(conversationId:string):Promise<string|null>{
 const session=await getSession();if(!session)return null;
 const {data}=await session.supabase.rpc("conversation_peer_read_at",{p_conversation:conversationId});
 return typeof data==="string"?data:null;
}