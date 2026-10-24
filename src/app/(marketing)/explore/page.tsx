import { redirect } from "next/navigation";

// "Explore People" opens the real discovery screen. Signed-out visitors are sent
// to sign in first and brought back here afterwards.
export default function ExplorePage() {
  redirect("/discover");
}
