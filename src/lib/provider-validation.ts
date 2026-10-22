/** Input rules for provider applications and offerings. The database enforces the same limits again. */

export const OFFERING_DURATIONS = [15, 20, 30, 45, 60, 90, 120] as const;
export const OFFERING_KINDS = ["text", "voice"] as const;
export type OfferingKind = (typeof OFFERING_KINDS)[number];

export const MIN_PRICE_MINOR = 100; // NGN 1
export const MAX_PRICE_MINOR = 100_000_000; // NGN 1,000,000

export function validateHeadline(raw: string): string | null {
  const v = raw.trim();
  if (!v) return "Add a short headline, for example “Career coach for new managers”.";
  if (v.length > 120) return "Headlines can be at most 120 characters.";
  return null;
}

export function validateAbout(raw: string): string | null {
  const v = raw.trim();
  if (!v) return "Tell people about yourself and how you can help.";
  if (v.length > 2000) return "This can be at most 2000 characters.";
  return null;
}

export function parseLanguages(raw: string): string[] {
  const seen = new Set<string>();
  for (const part of raw.split(",")) {
    const v = part.trim().replace(/\s+/g, " ");
    if (v && v.length <= 30) seen.add(v);
  }
  return [...seen].slice(0, 10);
}

/** "5000", "5,000" or "5000.50" (naira) to kobo. Returns null when it isn't a valid amount. */
export function nairaToMinor(raw: string): number | null {
  const cleaned = raw.trim().replace(/[₦,\s]/g, "");
  if (!/^\d+(\.\d{1,2})?$/.test(cleaned)) return null;
  const minor = Math.round(Number(cleaned) * 100);
  return Number.isSafeInteger(minor) ? minor : null;
}

export type OfferingInput = {
  kind: OfferingKind;
  title: string;
  description: string | null;
  durationMinutes: number;
  priceMinor: number;
  topicId: string | null;
};

export function validateOffering(form: {
  kind: string;
  title: string;
  description: string;
  duration: string;
  price: string;
  topicId: string;
}): { value: OfferingInput | null; errors: Record<string, string> } {
  const errors: Record<string, string> = {};
  const kind = form.kind as OfferingKind;
  if (!OFFERING_KINDS.includes(kind)) errors.kind = "Choose text or voice.";

  const title = form.title.trim();
  if (!title) errors.title = "Give your conversation a title.";
  else if (title.length > 80) errors.title = "Titles can be at most 80 characters.";

  const description = form.description.trim();
  if (description.length > 500) errors.description = "Descriptions can be at most 500 characters.";

  const durationMinutes = Number.parseInt(form.duration, 10);
  if (!OFFERING_DURATIONS.includes(durationMinutes as (typeof OFFERING_DURATIONS)[number])) {
    errors.duration = "Choose how long the conversation lasts.";
  }

  const priceMinor = nairaToMinor(form.price);
  if (priceMinor === null) errors.price = "Enter a price in naira, for example 5000.";
  else if (priceMinor < MIN_PRICE_MINOR) errors.price = "The lowest price is ₦1.";
  else if (priceMinor > MAX_PRICE_MINOR) errors.price = "The highest price is ₦1,000,000.";

  const topicId = form.topicId && /^[0-9a-f-]{36}$/i.test(form.topicId) ? form.topicId : null;

  if (Object.keys(errors).length) return { value: null, errors };
  return {
    value: {
      kind,
      title,
      description: description || null,
      durationMinutes,
      priceMinor: priceMinor!,
      topicId,
    },
    errors,
  };
}

/** What a provider sees on an offering in their own list. */
export function offeringStatus(o: {
  is_active: boolean;
  accepts_bookings: boolean;
  requires_subscription: boolean;
}, providerApproved: boolean): { label: string; hint: string } {
  if (!o.is_active) return { label: "Paused", hint: "Hidden from everyone. Resume it any time." };
  if (!providerApproved) return { label: "Waiting for approval", hint: "It goes live once your provider profile is approved." };
  if (o.accepts_bookings) return { label: "Live", hint: "People can find and book this." };
  if (o.requires_subscription) {
    return { label: "Needs a subscription", hint: "Not taking new bookings until your subscription is active. Existing bookings and history are kept." };
  }
  return { label: "Not available", hint: "This isn't visible right now." };
}
