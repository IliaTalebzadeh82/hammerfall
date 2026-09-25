"use client";

import Link from "next/link";
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
} from "react";
import { Button } from "@/components/ui/button";
import { errorMessage, getUsers, sendCommand } from "@/lib/api/client";
import type { Intention, Operation, User } from "@/lib/api/types";
import { PENDING_KEY, readPending, retryAllowed } from "@/lib/intentions";

type Outcome = {
  auctionId: number;
  message: string;
  success: boolean;
  revision: number;
};
type Session = {
  users: User[];
  actorId: number | null;
  selectActor: (id: number) => void;
  pending: Intention | null;
  phase: "ready" | "pending" | "ambiguous";
  ready: boolean;
  issue: string;
  outcome: Outcome | null;
  blocked: boolean;
  submit: (
    auctionId: number,
    operation: Operation,
    amount: number,
  ) => Promise<void>;
  retry: () => Promise<void>;
  abandon: () => void;
  clearIssue: () => void;
  usersError: boolean;
  usersLoading: boolean;
  moreUsers: () => void;
  usersNext: number | null;
};
const Context = createContext<Session | null>(null);
export function useAuctionSession() {
  const session = useContext(Context);
  if (!session) throw new Error("AuctionSession is required");
  return session;
}
export function AuctionSession({ children }: { children: React.ReactNode }) {
  const [users, setUsers] = useState<User[]>([]);
  const [usersNext, setUsersNext] = useState<number | null>(null);
  const [usersError, setUsersError] = useState(false);
  const [usersLoading, setUsersLoading] = useState(true);
  const [actorId, setActorId] = useState<number | null>(null);
  const [pending, setPending] = useState<Intention | null>(null);
  const [phase, setPhase] = useState<Session["phase"]>("ready");
  const [ready, setReady] = useState(false);
  const [issue, setIssue] = useState("");
  const [outcome, setOutcome] = useState<Outcome | null>(null);
  const inFlight = useRef(false);
  const commandRef = useRef<Intention | null>(null);
  const revision = useRef(0);
  const loadUsers = useCallback(async (after?: number) => {
    setUsersLoading(true);
    setUsersError(false);
    try {
      const page = await getUsers(after);
      setUsers((previous) =>
        after ? [...previous, ...page.items] : page.items,
      );
      setUsersNext(page.next);
    } catch {
      setUsersError(true);
    } finally {
      setUsersLoading(false);
    }
  }, []);
  useEffect(() => {
    try {
      const stored = localStorage.getItem("hammerfall.actor");
      if (stored && Number.isSafeInteger(Number(stored)) && Number(stored) > 0)
        setActorId(Number(stored));
      const command = readPending(sessionStorage);
      if (command) {
        commandRef.current = command;
        setPending(command);
        setActorId(command.actorId);
        setPhase("ambiguous");
      }
    } catch {
      setIssue(
        "Saved retry information could not be read. Review auction state before clearing it.",
      );
    }
    setReady(true);
    void loadUsers();
  }, [loadUsers]);
  const selectActor = (id: number) => {
    if (commandRef.current || inFlight.current) return;
    setActorId(id);
    setOutcome(null);
    try {
      localStorage.setItem("hammerfall.actor", String(id));
    } catch {
      /* Current tab can still select an actor. */
    }
  };
  const execute = async (command: Intention) => {
    if (inFlight.current) return;
    inFlight.current = true;
    commandRef.current = command;
    setPending(command);
    setPhase("pending");
    setOutcome(null);
    try {
      // Save before transmission. If storage fails, no new HTTP command is sent.
      sessionStorage.setItem(PENDING_KEY, JSON.stringify(command));
      setIssue("");
    } catch {
      setIssue(
        "Retry information could not be saved. No request was sent. Enable session storage before bidding.",
      );
      setPhase("ambiguous");
      inFlight.current = false;
      return;
    }
    try {
      const response = await sendCommand(command);
      setOutcome({
        auctionId: command.auctionId,
        success: response.success,
        revision: ++revision.current,
        message: `${response.replayed ? "Previous result recovered safely. " : ""}${
          response.success
            ? command.operation === "bid"
              ? "Your bid was accepted. Check the refreshed current leader below."
              : "Your maximum bid was accepted. Check the refreshed auction state."
            : errorMessage(response.error)
        }`,
      });
      try {
        sessionStorage.removeItem(PENDING_KEY);
        commandRef.current = null;
        setPending(null);
        setPhase("ready");
      } catch {
        setIssue(
          "The result is confirmed, but saved retry information could not be cleared. Clear it before another command.",
        );
        setPhase("ambiguous");
      }
    } catch {
      setPhase("ambiguous");
    } finally {
      inFlight.current = false;
    }
  };
  const submit: Session["submit"] = async (auctionId, operation, amount) => {
    if (!ready || !actorId || issue || commandRef.current || inFlight.current)
      return;
    let key: string;
    try {
      key = crypto.randomUUID();
    } catch {
      setIssue(
        "Secure key generation is unavailable. Open this demo on localhost or HTTPS.",
      );
      return;
    }
    await execute({
      key,
      auctionId,
      actorId,
      operation,
      amount,
      createdAt: Date.now(),
    });
  };
  const retry = async () => {
    const command = commandRef.current;
    if (command && retryAllowed(command)) await execute(command);
  };
  const abandon = () => {
    if (inFlight.current) return;
    try {
      sessionStorage.removeItem(PENDING_KEY);
    } catch {
      setIssue("Saved retry information could not be cleared.");
      return;
    }
    const auctionId = commandRef.current?.auctionId;
    commandRef.current = null;
    setPending(null);
    setPhase("ready");
    setIssue("");
    if (auctionId)
      setOutcome({
        auctionId,
        success: false,
        revision: ++revision.current,
        message:
          "The attempt was abandoned, not cancelled on the server. Review refreshed state before another bid.",
      });
  };
  return (
    <Context.Provider
      value={{
        users,
        actorId,
        selectActor,
        pending,
        phase,
        ready,
        issue,
        outcome,
        blocked: !ready || !!pending || !!issue,
        submit,
        retry,
        abandon,
        clearIssue: abandon,
        usersError,
        usersLoading,
        usersNext,
        moreUsers: () =>
          void loadUsers(usersError ? undefined : (usersNext ?? undefined)),
      }}
    >
      {children}
    </Context.Provider>
  );
}

export function ApplicationShell({ children }: { children: React.ReactNode }) {
  const s = useAuctionSession();
  const [confirmAbandon, setConfirmAbandon] = useState(false);
  const knownActor = s.users.some((user) => user.id === s.actorId);
  return (
    <>
      <a href="#main" className="skip-link">
        Skip to content
      </a>
      <header className="site-header">
        <div className="shell header-inner">
          <Link
            href="/auctions"
            className="wordmark"
            aria-label="Hammerfall auctions"
          >
            <span aria-hidden="true" className="brand-mark">
              H
            </span>{" "}
            Hammerfall<span className="brand-period">.</span>
          </Link>
          <nav aria-label="Main">
            <Link href="/auctions" className="nav-link">
              Auctions
            </Link>
          </nav>
          <div className="actor-control">
            <label htmlFor="demo-actor">Demo bidder</label>
            <select
              id="demo-actor"
              value={s.actorId ?? ""}
              disabled={s.blocked || s.usersLoading}
              onChange={(event) => s.selectActor(Number(event.target.value))}
            >
              <option value="" disabled>
                {s.usersLoading ? "Loading bidders…" : "Choose a bidder"}
              </option>
              {!knownActor && s.actorId && (
                <option value={s.actorId}>
                  Bidder #{s.actorId} · saved selection
                </option>
              )}
              {s.users.map((user) => (
                <option key={user.id} value={user.id}>
                  {user.name} · #{user.id}
                </option>
              ))}
            </select>
            {(s.usersNext || s.usersError) && (
              <Button
                variant="link"
                disabled={s.usersLoading}
                onClick={s.moreUsers}
              >
                {s.usersError ? "Retry bidders" : "More bidders"}
              </Button>
            )}
            {!s.usersLoading && !s.usersError && s.users.length === 0 && (
              <span role="status">No demo users available.</span>
            )}
          </div>
        </div>
        <div className="demo-strip">
          <div className="shell">
            Demo mode · Selecting a bidder does not authenticate you. It only
            chooses the actor ID used by requests.
          </div>
        </div>
      </header>
      <div className="shell">
        {s.issue && (
          <section role="alert" className="notice warning">
            <p>{s.issue}</p>
            <Button variant="outline" onClick={s.clearIssue}>
              Clear saved retry information
            </Button>
          </section>
        )}
        {s.pending && (
          <section
            className="notice warning"
            aria-label="Unconfirmed attempt"
            aria-live="polite"
          >
            <strong>
              {s.phase === "pending"
                ? "Awaiting confirmation…"
                : "We couldn’t confirm whether this attempt was processed."}
            </strong>
            <p>
              Keep this attempt unchanged. Refreshing the auction does not
              confirm or cancel it. It belongs to bidder #{s.pending.actorId}.
            </p>
            <div className="actions">
              <Link href={`/auctions/${s.pending.auctionId}`}>
                Open this auction →
              </Link>
              <Button
                disabled={s.phase === "pending" || !retryAllowed(s.pending)}
                onClick={() => void s.retry()}
              >
                Retry safely
              </Button>
              <Button
                variant="outline"
                disabled={s.phase === "pending"}
                onClick={() => setConfirmAbandon(true)}
              >
                Review abandonment
              </Button>
            </div>
            {!retryAllowed(s.pending) && (
              <p>
                This saved attempt is outside the one-hour retry window. Review
                state before abandoning it; the original may have succeeded.
              </p>
            )}
            {confirmAbandon && (
              <div className="abandon-confirm">
                <p>
                  Abandoning does not cancel a bid already accepted by the
                  server. A new bid could be an additional commitment.
                </p>
                <div className="actions">
                  <Button
                    variant="destructive"
                    onClick={() => {
                      s.abandon();
                      setConfirmAbandon(false);
                    }}
                  >
                    Abandon attempt and refresh
                  </Button>
                  <Button
                    variant="outline"
                    onClick={() => setConfirmAbandon(false)}
                  >
                    Keep attempt
                  </Button>
                </div>
              </div>
            )}
          </section>
        )}
      </div>
      <main id="main" className="shell main-content">
        {children}
      </main>
      <footer className="shell site-footer">
        <span className="wordmark">Hammerfall.</span>
        <p>Considered objects. Committed bids.</p>
        <p>Updates appear when you refresh. This demo has no authentication.</p>
      </footer>
    </>
  );
}
