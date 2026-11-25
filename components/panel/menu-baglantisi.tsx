"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  BellIcon,
  Building2Icon,
  CalculatorIcon,
  CalendarDaysIcon,
  ClockPlusIcon,
  HardHatIcon,
  HouseIcon,
  IdCardIcon,
  MessageCircleQuestionIcon,
  ScaleIcon,
  SettingsIcon,
  TreePalmIcon,
  UploadIcon,
  UserCogIcon,
  UsersIcon,
  type LucideIcon,
} from "lucide-react";
import type { MenuSimgesi } from "@/lib/menu";
import { cn } from "@/lib/utils";

const SIMGELER: Record<MenuSimgesi, LucideIcon> = {
  ana: HouseIcon,
  uyari: BellIcon,
  soru: MessageCircleQuestionIcon,
  itiraz: ScaleIcon,
  puantaj: CalculatorIcon,
  izin: TreePalmIcon,
  vardiya: CalendarDaysIcon,
  mesai: ClockPlusIcon,
  departman: Building2Icon,
  calisan: UsersIcon,
  kart: IdCardIcon,
  isg: HardHatIcon,
  aktarim: UploadIcon,
  kullanici: UserCogIcon,
  ayar: SettingsIcon,
};

// Menüdeki bir bağlantı. Açık olan sayfa vurgulanır; bekleyen iş varsa sağda sayısı görünür.
// usePathname tarayıcıdaki adresi okuduğu için bu bileşen "use client".
export function MenuBaglantisi({
  yol,
  baslik,
  simge,
  sayi,
}: {
  yol: string;
  baslik: string;
  simge: MenuSimgesi;
  sayi?: number;
}) {
  const adres = usePathname();
  const acik = yol === "/" ? adres === "/" : adres === yol || adres.startsWith(`${yol}/`);
  const Simge = SIMGELER[simge];

  return (
    <Link
      href={yol}
      aria-current={acik ? "page" : undefined}
      className={cn(
        "group flex items-center gap-3 rounded-lg px-3 py-1.5 text-sm whitespace-nowrap transition-colors outline-none",
        "text-sidebar-foreground/80 hover:bg-sidebar-foreground/[0.07] hover:text-sidebar-foreground",
        "focus-visible:ring-2 focus-visible:ring-sidebar-ring",
        acik && "bg-sidebar-accent font-medium text-sidebar-accent-foreground hover:bg-sidebar-accent hover:text-sidebar-accent-foreground",
      )}
    >
      <Simge className="size-4 shrink-0" aria-hidden />
      <span className="flex-1">{baslik}</span>
      {sayi ? (
        <span
          className="rounded-full bg-sidebar-primary/15 px-2 py-0.5 text-xs font-medium tabular-nums text-sidebar-primary"
          aria-label={`${sayi} bekleyen`}
        >
          {sayi}
        </span>
      ) : null}
    </Link>
  );
}
