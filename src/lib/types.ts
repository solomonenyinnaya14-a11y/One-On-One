export type ProfileRow = {
  id: string;
  username: string | null;
  display_name: string;
  avatar_path: string | null;
  bio: string | null;
  interests: string[];
  expertise: string | null;
  accepts_free_chats: boolean;
  is_discoverable?: boolean;
  onboarding_completed_at?: string | null;
  status?: string;
  created_at: string;
  last_seen_at?: string | null;
  show_online_status?: boolean;
};

export type ProviderCard = {
  user_id: string;
  headline: string | null;
  about: string | null;
  languages: string[];
  rating_count: number;
  rating_sum: number;
};

export type OfferingRow = {
  id: string;
  kind: "text" | "voice";
  title: string;
  description: string | null;
  duration_minutes: number;
  price_minor: number;
  currency: string;
  accepts_bookings: boolean;
};
