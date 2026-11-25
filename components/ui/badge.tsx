import { mergeProps } from "@base-ui/react/merge-props"
import { useRender } from "@base-ui/react/use-render"
import { cva, type VariantProps } from "class-variance-authority"
import { cn } from "cn"

const badgeVariants = cva(
  // Durum rozetiyle (DurumRozeti) aynı dil: yuvarlak, küçük kalın yazı, kendi renginde ince çerçeve
  "group/badge inline-flex h-[1.375rem] w-fit shrink-0 items-center justify-center gap-1 overflow-hidden rounded-full px-2 text-xs font-semibold tracking-[0.01em] whitespace-nowrap ring-1 ring-inset ring-[color-mix(in_oklab,currentColor_22%,transparent)] transition-colors focus-visible:ring-[3px] focus-visible:ring-ring/50 [&>svg]:pointer-events-none [&>svg]:size-3!",
  {
    variants: {
      variant: {
        // Bekleyen / dikkat isteyen (sayı rozetleri, "Başlayacak")
        default: "bg-dikkat-zemin text-dikkat [a]:hover:bg-dikkat-zemin/80",
        // Bilgi etiketi (izin türü, "İlk değer")
        secondary: "bg-accent text-accent-foreground [a]:hover:bg-accent/80",
        // Çalışan aleyhine / eksik
        destructive: "bg-kotu-zemin text-kotu [a]:hover:bg-kotu-zemin/80",
        // Sakin etiket ("İzinli", "Ayrıldı", "Yazılı onay yok")
        outline: "bg-card text-muted-foreground [a]:hover:bg-muted",
        ghost: "ring-0 hover:bg-muted hover:text-muted-foreground dark:hover:bg-muted/50",
        link: "ring-0 text-primary underline-offset-4 hover:underline",
      },
    },
    defaultVariants: {
      variant: "default",
    },
  }
)

function Badge({
  className,
  variant = "default",
  render,
  ...props
}: useRender.ComponentProps<"span"> & VariantProps<typeof badgeVariants>) {
  return useRender({
    defaultTagName: "span",
    props: mergeProps<"span">(
      {
        className: cn(badgeVariants({ variant }), className),
      },
      props
    ),
    render,
    state: {
      slot: "badge",
      variant,
    },
  })
}

export { Badge, badgeVariants }
