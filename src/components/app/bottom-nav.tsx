"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { activeTab, appTabs, type AppTabKey } from "@/lib/navigation";

const icons: Record<AppTabKey, React.ReactNode> = {
  home: <path d="M3 11.5 12 4l9 7.5V20a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z" />,
  discover: (
    <>
      <circle cx="11" cy="11" r="6.5" />
      <path d="m16 16 5 5" />
    </>
  ),
  create: (
    <>
      <circle cx="12" cy="12" r="9" />
      <path d="M12 8v8M8 12h8" />
    </>
  ),
  inbox: <path d="M4 5h16a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H9l-5 4V6a1 1 0 0 1 1-1z" />,
  profile: (
    <>
      <circle cx="12" cy="8" r="4" />
      <path d="M4 21c0-4.4 3.6-7 8-7s8 2.6 8 7" />
    </>
  ),
};

export function BottomNav({ unread = 0 }: { unread?: number }) {
  const pathname = usePathname();
  const current = activeTab(pathname);

  return (
    <nav
      aria-label="Main"
      className="fixed inset-x-0 bottom-0 z-40 border-t border-grey-200 bg-white/90 pb-[env(safe-area-inset-bottom)] backdrop-blur-md"
    >
      <ul className="mx-auto flex max-w-2xl">
        {appTabs.map((tab) => {
          const isCurrent = current === tab.key;
          const badge = tab.key === "inbox" && unread > 0;
          return (
            <li key={tab.key} className="flex-1">
              <Link
                href={tab.href}
                aria-current={isCurrent ? "page" : undefined}
                className={`relative flex min-h-16 flex-col items-center justify-center gap-1 text-xs font-semibold ${
                  isCurrent ? "text-navy-900" : "text-grey-600"
                }`}
              >
                <svg
                  viewBox="0 0 24 24"
                  aria-hidden="true"
                  focusable="false"
                  className="h-6 w-6"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth={isCurrent ? 2.4 : 1.8}
                  strokeLinecap="round"
                  strokeLinejoin="round"
                >
                  {icons[tab.key]}
                </svg>
                <span>{tab.label}</span>
                {badge ? (
                  <span className="absolute right-[calc(50%-1.6rem)] top-2 min-w-5 rounded-full bg-navy-900 px-1.5 text-center text-[0.7rem] leading-5 text-white">
                    <span aria-hidden="true">{unread > 99 ? "99+" : unread}</span>
                    <span className="sr-only">{unread} unread</span>
                  </span>
                ) : null}
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}
