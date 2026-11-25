"use client"

import { Toaster as Sonner, type ToasterProps } from "sonner"
import { CircleCheckIcon, InfoIcon, TriangleAlertIcon, OctagonXIcon, Loader2Icon } from "lucide-react"

// Tema, kök düzenden (çerezdeki seçim) gelir.
const Toaster = ({ ...props }: ToasterProps) => {
  return (
    <Sonner
      className="toaster group"
      icons={{
        success: <CircleCheckIcon className="size-4" />,
        info: <InfoIcon className="size-4" />,
        warning: <TriangleAlertIcon className="size-4" />,
        error: <OctagonXIcon className="size-4" />,
        loading: <Loader2Icon className="size-4 animate-spin" />,
      }}
      style={
        {
          "--normal-bg": "var(--popover)",
          "--normal-text": "var(--popover-foreground)",
          "--normal-border": "var(--border)",
          "--border-radius": "var(--radius)",
        } as React.CSSProperties
      }
      // Bildirimler: türün renginde sol çizgi ve simge; köşeler ve gölge uygulamanın diliyle
      toastOptions={{
        classNames: {
          toast: "cn-toast !rounded-xl !border-l-4 !shadow-lg !shadow-[#1f2357]/15",
          success: "!border-l-iyi [&_[data-icon]]:!text-iyi",
          error: "!border-l-kotu [&_[data-icon]]:!text-kotu",
          warning: "!border-l-dikkat [&_[data-icon]]:!text-dikkat",
          info: "!border-l-vurgu [&_[data-icon]]:!text-vurgu",
        },
      }}
      {...props}
    />
  )
}

export { Toaster }
