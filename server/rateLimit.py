"""
Brute-force protection for POST /v1/security/auth

Two independent limits, both in memory and per process (the server runs as a single uvicorn process):
- per client IP, enforced by slowapi: AUTH_RATE_LIMIT
- per username: after MAX_FAILURES failed logins within FAILURE_WINDOW_SECONDS, the username is
  locked for LOCKOUT_SECONDS and the endpoint answers 429 without calling Keycloak
Both answer 429 with the same fixed detail and a Retry-After header.
"""
import threading
import time
from collections import deque
from datetime import datetime, UTC
from fastapi.requests import Request # pyright: ignore[reportMissingImports]
from fastapi.responses import JSONResponse # pyright: ignore[reportMissingImports]
from slowapi import Limiter # pyright: ignore[reportMissingImports]
from slowapi.errors import RateLimitExceeded # pyright: ignore[reportMissingImports]
from slowapi.util import get_remote_address # pyright: ignore[reportMissingImports]
# Initialize logger at the top so it's available everywhere
from logger.loggerFactory import logger_factory
logger = logger_factory.get_logger('rateLimit')

AUTH_RATE_LIMIT = "5/minute;30/hour"
MAX_FAILURES = 10
FAILURE_WINDOW_SECONDS = 15 * 60
LOCKOUT_SECONDS = 15 * 60
TOO_MANY_ATTEMPTS_DETAIL = "Too many login attempts, try again later"
# Above this many tracked usernames, entries with no recent failure and no active lock are dropped
_MAX_TRACKED_USERNAMES = 10_000

# Keyed on the TCP peer address (request.client.host): X-Forwarded-For is not trusted,
# the server is exposed directly by uvicorn with no reverse proxy in front
limiter = Limiter(key_func=get_remote_address)


def client_ip(request: Request) -> str:
    return get_remote_address(request)


class LoginFailureTracker:
    """Failed logins per (lowercased) username, with a temporary lockout"""

    def __init__(self, max_failures: int = MAX_FAILURES, window_seconds: int = FAILURE_WINDOW_SECONDS,
                 lockout_seconds: int = LOCKOUT_SECONDS):
        self.max_failures = max_failures
        self.window_seconds = window_seconds
        self.lockout_seconds = lockout_seconds
        self._lock = threading.Lock()
        self._failures: dict[str, deque] = {}
        self._locked_until: dict[str, float] = {}

    @staticmethod
    def normalize(username: str) -> str:
        return username.lower()

    def lock_remaining(self, username: str) -> int:
        """Seconds left on the username's lockout, 0 if it is not locked"""
        with self._lock:
            locked_until = self._locked_until.get(username)
            if locked_until is None:
                return 0
            remaining = locked_until - time.monotonic()
            if remaining <= 0:
                del self._locked_until[username]
                return 0
            return max(1, int(remaining + 0.999))

    def record_failure(self, username: str) -> bool:
        """Count a failed login; returns True if this failure locked the username"""
        with self._lock:
            now = time.monotonic()
            failures = self._failures.setdefault(username, deque())
            while failures and now - failures[0] > self.window_seconds:
                failures.popleft()
            failures.append(now)
            locked = len(failures) >= self.max_failures
            if locked:
                self._locked_until[username] = now + self.lockout_seconds
                del self._failures[username]
            if len(self._failures) > _MAX_TRACKED_USERNAMES:
                self._purge(now)
            return locked

    def reset(self, username: str):
        """Successful login: forget the username's failures"""
        with self._lock:
            self._failures.pop(username, None)
            self._locked_until.pop(username, None)

    def reset_all(self):
        with self._lock:
            self._failures.clear()
            self._locked_until.clear()

    def _purge(self, now: float):
        for name in [n for n, f in self._failures.items() if not f or now - f[-1] > self.window_seconds]:
            del self._failures[name]
        for name in [n for n, until in self._locked_until.items() if until <= now]:
            del self._locked_until[name]


failure_tracker = LoginFailureTracker()


def too_many_attempts_response(request: Request, retry_after: int) -> JSONResponse:
    """429 in the same shape as authServer's HTTPException handler, with a fixed detail"""
    return JSONResponse(
        status_code=429,
        content={
            "detail": TOO_MANY_ATTEMPTS_DETAIL,
            "path": request.url.path,
            "timestamp": datetime.now(UTC).isoformat(),
        },
        headers={"Retry-After": str(max(1, int(retry_after)))},
    )


def rate_limit_exceeded_handler(request: Request, exc: RateLimitExceeded) -> JSONResponse:
    """slowapi IP limit breached: 429 with Retry-After until the breached window resets"""
    logger.warning(f"Login rate limit ({exc.limit.limit}) exceeded by client {client_ip(request)}")
    try:
        breached = request.state.view_rate_limit
        reset_at, _remaining = request.app.state.limiter.limiter.get_window_stats(breached[0], *breached[1])
        retry_after = int(reset_at - time.time()) + 1
    except Exception:
        retry_after = exc.limit.limit.get_expiry()
    return too_many_attempts_response(request, retry_after)
