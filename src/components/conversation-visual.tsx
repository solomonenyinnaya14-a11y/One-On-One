/*
  An illustration of a conversation: two people trading messages, then a voice
  line. It uses grey bars instead of words on purpose, so it never reads as
  real messages, real people or real activity.
*/
import type { CSSProperties } from "react";

const WAVE = [6, 14, 22, 10, 28, 18, 8, 24, 32, 16, 10, 26, 20, 12, 30, 18, 8, 22, 14, 6];

function Bars({ widths, tone }: { widths: string[]; tone: "light" | "dark" }) {
  const color = tone === "dark" ? "bg-white/45" : "bg-grey-300";
  return (
    <div className="space-y-2">
      {widths.map((w, i) => (
        <div key={i} className={`h-2 rounded-full ${color}`} style={{ width: w }} />
      ))}
    </div>
  );
}

export function ConversationVisual() {
  return (
    <figure className="w-full max-w-md">
      <div
        aria-hidden="true"
        className="rounded-[2rem] border border-grey-200 bg-grey-50 p-5 sm:p-6"
      >
        <div className="space-y-4">
          <div className="build-in flex items-end gap-3" style={{ "--delay": "250ms" } as CSSProperties}>
            <span className="h-9 w-9 shrink-0 rounded-full border-2 border-ink bg-paper" />
            <div className="w-[78%] rounded-3xl rounded-bl-md border border-grey-200 bg-paper px-5 py-4">
              <Bars widths={["92%", "64%"]} tone="light" />
            </div>
          </div>

          <div
            className="build-in flex items-end justify-end gap-3"
            style={{ "--delay": "950ms" } as CSSProperties}
          >
            <div className="w-[70%] rounded-3xl rounded-br-md bg-navy-900 px-5 py-4">
              <Bars widths={["88%", "72%", "40%"]} tone="dark" />
            </div>
            <span className="h-9 w-9 shrink-0 rounded-full bg-navy-900" />
          </div>

          <div
            className="build-in flex items-center gap-[3px] rounded-full border border-grey-200 bg-paper px-5 py-3"
            style={{ "--delay": "1650ms" } as CSSProperties}
          >
            <span className="mr-3 h-3 w-3 shrink-0 rounded-full bg-ink" />
            {WAVE.map((h, i) => (
              <span
                key={i}
                className="w-[3px] rounded-full bg-navy-900"
                style={{ height: `${h}px` }}
              />
            ))}
          </div>
        </div>
      </div>
      <figcaption className="mt-4 text-sm text-grey-600">
        Every conversation is text or voice, one person at a time.
      </figcaption>
    </figure>
  );
}
