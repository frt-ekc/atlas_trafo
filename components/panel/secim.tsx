import type { ComponentProps } from "react";
import { cn } from "@/lib/utils";

// Tarayıcının kendi açılır listesi, Input ile aynı görünümde.
// JavaScript gerektirmez; GET formlarında (süzgeçlerde) doğrudan çalışır.
export function Secim({ className, ...props }: ComponentProps<"select">) {
  return (
    <select
      // SuzgecFormu okur: sayfa yeniden çizilince React defaultValue'yu ekrana yansıtmaz
      data-varsayilan={props.defaultValue === undefined ? undefined : String(props.defaultValue)}
      className={cn(
        "h-9 rounded-lg border border-input bg-transparent px-2.5 text-sm outline-none transition-colors",
        "focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 dark:bg-input/30",
        className,
      )}
      {...props}
    />
  );
}
