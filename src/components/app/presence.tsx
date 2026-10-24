"use client";
import { useEffect,useState } from "react";
import { getPresence,updatePresence } from "@/app/(app)/safety-actions";
export function PresenceHeartbeat(){
 useEffect(()=>{const ping=()=>{if(document.visibilityState==="visible")void updatePresence();};ping();const timer=window.setInterval(ping,45000);document.addEventListener("visibilitychange",ping);return()=>{window.clearInterval(timer);document.removeEventListener("visibilitychange",ping);};},[]);
 return null;
}
export function OnlineStatus({lastSeenAt,targetId,showStatus=true,className=""}:{lastSeenAt?:string|null;targetId?:string;showStatus?:boolean;className?:string}){
 const [polledSeen,setPolledSeen]=useState<string|null>(null),[now,setNow]=useState(0);
 const seen=targetId?polledSeen:(lastSeenAt??null);
 useEffect(()=>{
  const clock=window.setInterval(()=>setNow(Date.now()),1000);let active=true;
  const refresh=async()=>{if(targetId){const next=await getPresence(targetId);if(active)setPolledSeen(next);}};
  if(targetId){void refresh();const poll=window.setInterval(()=>void refresh(),30000);return()=>{active=false;window.clearInterval(clock);window.clearInterval(poll);};}
  return()=>{active=false;window.clearInterval(clock);};
 },[targetId]);
 const online=showStatus&&Boolean(seen&&now>0&&now-new Date(seen).getTime()<120000);
 return <span className={`inline-flex items-center gap-1.5 text-xs ${className} ${online?"text-emerald-700":"text-grey-600"}`}><span aria-hidden="true" className={`h-2 w-2 rounded-full ${online?"bg-emerald-500":"bg-grey-300"}`}/>{online?"Online":"Offline"}</span>;
}