"use client";

import * as Popover from "@radix-ui/react-popover";
import { useState } from "react";

// The options inside are server-rendered <Link>s passed in as children, so this component owns
// nothing but the open/closed state. Radix handles focus, Escape and outside-click.
export function Facet({
  label,
  value,
  children,
}: {
  label: string;
  value?: string;
  children: React.ReactNode;
}) {
  const [open, setOpen] = useState(false);
  const active = Boolean(value);

  return (
    <Popover.Root open={open} onOpenChange={setOpen}>
      <Popover.Trigger
        className={`label flex items-center gap-2 border border-rule px-3 py-2 ${
          active ? "border-accent bg-accent text-on-accent" : "bg-paper text-ink hover:bg-paper-2"
        }`}
      >
        <span>{value ?? label}</span>
        <span aria-hidden className="text-[9px]">
          ▼
        </span>
      </Popover.Trigger>
      {/* Picking an option is a soft navigation, so without this the popover would stay open
          over the results it just changed. */}
      <Popover.Portal>
        <Popover.Content
          sideOffset={-1}
          align="start"
          onClick={() => setOpen(false)}
          className="z-50 max-h-80 min-w-56 overflow-y-auto border border-rule bg-paper shadow-[4px_4px_0_0_var(--rule)]"
        >
          <div className="label border-b border-rule-soft px-3 py-2 text-ink-3">{label}</div>
          {children}
        </Popover.Content>
      </Popover.Portal>
    </Popover.Root>
  );
}
