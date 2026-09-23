import { Button } from "@/components/ui/button";

export default function Home() {
  return (
    <main className="mx-auto flex min-h-svh max-w-3xl flex-col justify-center gap-6 px-6 py-16 sm:px-12">
      <p className="text-sm font-medium tracking-widest text-muted-foreground uppercase">
        In the making
      </p>
      <h1 className="text-5xl font-semibold tracking-tight sm:text-7xl">
        Hammerfall
      </h1>
      <p className="max-w-xl text-xl leading-relaxed text-muted-foreground">
        Every bid matters. We’re building a considered auction experience, one
        step at a time.
      </p>
      <div>
        <Button disabled size="lg">
          Auctions coming soon
        </Button>
      </div>
    </main>
  );
}
