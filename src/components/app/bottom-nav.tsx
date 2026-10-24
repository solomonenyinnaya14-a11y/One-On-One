"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { activeTab, appTabs, type AppTabKey } from "@/lib/navigation";
const icons: Record<AppTabKey, React.ReactNode> = {
  discover: <><circle cx="11" cy="11" r="6.5" /><path d="m16 16 5 5" /></>,
  requests: <><rect x="3" y="5" width="18" height="14" rx="2" /><path d="m4 7 8 6 8-6" /></>,
  messages: <path d="M4 5h16a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H9l-5 4V6a1 1 0 0 1 1-1z" />,
  profile: <><circle cx="12" cy="8" r="4" /><path d="M4 21c0-4.4 3.6-7 8-7s8 2.6 8 7" /></>,
};
export function BottomNav({ unread = 0 }: { unread?: number }) {
  const current = activeTab(usePathname());
  return <nav aria-label="Main" className="fixed inset-x-0 bottom-0 z-40 border-t border-grey-200 bg-white/95 pb-[env(safe-area-inset-bottom)] backdrop-blur-md">
    <ul className="mx-auto flex max-w-2xl">{appTabs.map((tab) => {
      const active = current === tab.key, badge = tab.key === "messages" && unread > 0;
      return <li key={tab.key} className="flex-1"><Link href={tab.href} aria-current={active ? "page" : undefined} className={`relative flex min-h-16 flex-col items-center justify-center gap-1 text-xs font-semibold transition-colors ${active ? "text-navy-900" : "text-grey-600 hover:text-ink"}`}>
        <svg viewBox="0 0 24 24" aria-hidden="true" className="h-6 w-6" fill="none" stroke="currentColor" strokeWidth={active ? 2.4 : 1.8} strokeLinecap="round" strokeLinejoin="round">{icons[tab.key]}</svg><span>{tab.label}</span>
        {badge ? <span className="absolute right-[calc(50%-1.6rem)] top-2 min-w-5 rounded-full bg-navy-900 px-1.5 text-center text-[0.7rem] leading-5 text-white"><span aria-hidden="true">{unread > 99 ? "99+" : unread}</span><span className="sr-only">{unread} unread</span></span> : null}
      </Link></li>;
    })}</ul>
  </nav>;
}