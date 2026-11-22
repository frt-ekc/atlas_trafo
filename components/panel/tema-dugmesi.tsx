"use client";

import { MoonIcon, SunIcon } from "lucide-react";
import { useRouter } from "next/navigation";
import { useTransition } from "react";
import type { Tema } from "@/lib/tema";

// Açık / koyu tema düğmesi. Seçim bir yıl çerezde kalır (kişisel tercih).
// Renk hemen değişir; router.refresh sunucunun da yeni temayla çizmesini sağlar (bildirimler dahil).
export function TemaDugmesi({ tema }: { tema: Tema }) {
  const router = useRouter();
  const [, gecis] = useTransition();
  const sonraki: Tema = tema === "koyu" ? "acik" : "koyu";

  function degistir() {
    document.cookie = `tema=${sonraki}; path=/; max-age=31536000; samesite=lax`;
    document.documentElement.classList.toggle("dark", sonraki === "koyu");
    gecis(() => router.refresh());
  }

  return (
    <button
      type="button"
      onClick={degistir}
      className="grid size-9 place-items-center rounded-full border bg-card/60 text-muted-foreground transition-colors outline-none hover:text-foreground focus-visible:ring-2 focus-visible:ring-ring"
      aria-label={sonraki === "koyu" ? "Koyu temaya geç" : "Açık temaya geç"}
      title={sonraki === "koyu" ? "Koyu tema" : "Açık tema"}
    >
      {tema === "koyu" ? <SunIcon className="size-4" /> : <MoonIcon className="size-4" />}
    </button>
  );
}
