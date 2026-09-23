import { redirect } from "next/navigation";

// The postings list is the front door; the charts live one click away at /intelligence.
export default function Home() {
  redirect("/postings");
}
