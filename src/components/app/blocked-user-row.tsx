"use client";
import {useState,useTransition} from "react";
import {useRouter} from "next/navigation";
import {Avatar} from "@/components/ui/avatar";
import {unblockUser} from "@/app/(app)/safety-actions";
export function BlockedUserRow({id,name,username,avatarPath}:{id:string;name:string;username:string|null;avatarPath:string|null}){
 const [error,setError]=useState<string|null>(null),[pending,start]=useTransition(),router=useRouter();
 return <li className="card flex items-center gap-3 p-3"><Avatar name={name} path={avatarPath}/><div className="min-w-0 flex-1"><p className="truncate font-semibold">{name}</p>{username?<p className="truncate text-sm text-grey-600">@{username}</p>:null}{error?<p role="alert" className="text-xs text-red-700">{error}</p>:null}</div><button type="button" disabled={pending} onClick={()=>start(async()=>{const r=await unblockUser(id);if(r.error)setError(r.error);else router.refresh();})} className="min-h-10 rounded-full border border-grey-300 px-4 text-sm font-semibold disabled:opacity-60">{pending?"…":"Unblock"}</button></li>;
}