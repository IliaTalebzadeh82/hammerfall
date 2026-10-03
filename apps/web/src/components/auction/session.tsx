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
import {
  ApiFailure,
  errorMessage,
  getSession,
  getUsers,
  login,
  logout,
  sendCommand,
} from "@/lib/api/client";
import type {
  AuthenticatedUser,
  Intention,
  Operation,
  User,
} from "@/lib/api/types";
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
  actor: AuthenticatedUser | null;
  signIn: (login: string, password: string) => Promise<void>;
  signOut: () => Promise<void>;
  authError: string;
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
  const [actor, setActor] = useState<AuthenticatedUser | null>(null);
  const [csrfToken, setCsrfToken] = useState("");
  const [authError, setAuthError] = useState("");
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
      const command = readPending(sessionStorage);
      if (command) {
        commandRef.current = command;
        setPending(command);
        setPhase("ambiguous");
      }
    } catch {
      setIssue(
        "Saved retry information could not be read. Review auction state before clearing it.",
      );
    }
    void getSession()
      .then((current) => {
        if (current) {
          setActor(current.user);
          setActorId(current.user.id);
          setCsrfToken(current.csrfToken);
        }
      })
      .catch(() =>
        setAuthError(
          "Could not check your session. Retry by refreshing the page.",
        ),
      )
      .finally(() => setReady(true));
    void loadUsers();
  }, [loadUsers]);
  const signIn = async (name: string, password: string) => {
    try {
      const current = await login(name, password);
      setActor(current.user);
      setActorId(current.user.id);
      setCsrfToken(current.csrfToken);
      setAuthError("");
    } catch {
      setAuthError("Sign in failed. Check your credentials and try again.");
    }
  };
  const signOut = async () => {
    if (inFlight.current) return;
    try {
      await logout(csrfToken);
      setActor(null);
      setActorId(null);
      setCsrfToken("");
      setAuthError("");
    } catch (error) {
      if (error instanceof ApiFailure && error.status === 401) {
        setActor(null);
        setActorId(null);
        setCsrfToken("");
        setAuthError("Session expired. Sign in again to continue.");
      } else {
        setAuthError("Sign out could not be confirmed. Refresh and try again.");
      }
    }
  };
  const execute = async (command: Intention) => {
    if (inFlight.current) return;
    if (!actorId || actorId !== command.actorId || !csrfToken) {
      setAuthError(
        `Sign in as bidder #${command.actorId} to recover this attempt.`,
      );
      return;
    }
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
      const response = await sendCommand(command, csrfToken);
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
    } catch (error) {
      if (error instanceof ApiFailure && error.status === 401) {
        setActor(null);
        setActorId(null);
        setCsrfToken("");
        setAuthError(
          `Session expired. Sign in as bidder #${command.actorId}, then retry this unchanged attempt.`,
        );
      }
      setPhase("ambiguous");
    } finally {
      inFlight.current = false;
    }
  };
  const submit: Session["submit"] = async (auctionId, operation, amount) => {
    if (
      !ready ||
      !actorId ||
      !csrfToken ||
      issue ||
      commandRef.current ||
      inFlight.current
    )
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
        actor,
        signIn,
        signOut,
        authError,
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
  const [loginName, setLoginName] = useState("");
  const [password, setPassword] = useState("");
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
            {s.actor ? (
              <>
                <span>
                  Signed in: {s.actor.name} · #{s.actor.id}
                </span>
                <Button variant="outline" onClick={() => void s.signOut()}>
                  Sign out
                </Button>
              </>
            ) : (
              <form
                onSubmit={(event) => {
                  event.preventDefault();
                  void s
                    .signIn(loginName, password)
                    .then(() => setPassword(""));
                }}
              >
                <label htmlFor="login-name">Login</label>
                <input
                  id="login-name"
                  autoComplete="username"
                  value={loginName}
                  onChange={(event) => setLoginName(event.target.value)}
                  required
                />
                <label htmlFor="login-password">Password</label>
                <input
                  id="login-password"
                  type="password"
                  autoComplete="current-password"
                  value={password}
                  onChange={(event) => setPassword(event.target.value)}
                  required
                />
                <Button type="submit" disabled={!s.ready}>
                  Sign in
                </Button>
              </form>
            )}
          </div>
        </div>
      </header>
      <div className="shell">
        {s.authError && (
          <section role="alert" className="notice warning">
            {s.authError}
          </section>
        )}
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
        <p>Auction details support live updates. Sign in before bidding.</p>
      </footer>
    </>
  );
}
