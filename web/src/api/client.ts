/**
 * SFTP Admin API client.
 *
 * - Base URL: VITE_API_BASE_URL env with a sane default; overridable per
 *   browser via localStorage (Settings screen).
 * - Auth: Bearer access token + HttpOnly refresh-token cookie. The access
 *   token is short-lived (15 min) and stored in memory + localStorage for
 *   page-reload survival. The refresh token lives in an HttpOnly cookie
 *   (XSS-resistant). On 401 the client silently calls /auth/refresh (cookie
 *   sent automatically via credentials:'include') and retries once.
 * - Public-permission guard: client-side mirror of the server's HTTP 422
 *   rule — permission "public" requires public_acknowledged === true.
 */
import {
  Account,
  AccountRequest,
  AdminIdentity,
  ApiError,
  HealthResponse,
  SyncResult,
  TokenPair,
} from './types';

const DEFAULT_API_BASE = '/api/v1';
const ACCESS_TOKEN_KEY = 'sftp.access_token';
const EXPIRES_AT_KEY = 'sftp.expires_at';
const REFRESH_LEAD_SECONDS = 60;
const API_BASE_OVERRIDE_KEY = 'sftp.api_base_override';

// ---- Base URL helpers ----

export function getApiBase(): string {
  const override =
    typeof localStorage !== 'undefined'
      ? localStorage.getItem(API_BASE_OVERRIDE_KEY)
      : null;
  const base = override || import.meta.env.VITE_API_BASE_URL || DEFAULT_API_BASE;
  return base.replace(/\/+$/, '');
}

export function setApiBaseOverride(value: string | null): void {
  if (value && value.trim()) {
    localStorage.setItem(API_BASE_OVERRIDE_KEY, value.trim());
  } else {
    localStorage.removeItem(API_BASE_OVERRIDE_KEY);
  }
}

export function getDefaultApiBase(): string {
  return (import.meta.env.VITE_API_BASE_URL || DEFAULT_API_BASE).replace(/\/+$/, '');
}

// ---- Access-token helpers (localStorage — short-lived, 15 min) ----
// The refresh token is stored in an HttpOnly cookie and is NOT accessible
// from JavaScript.

export function getAccessToken(): string | null {
  return localStorage.getItem(ACCESS_TOKEN_KEY);
}

export function isAuthenticated(): boolean {
  return getAccessToken() !== null;
}

function getExpiresAt(): number | null {
  const val = localStorage.getItem(EXPIRES_AT_KEY);
  if (!val) return null;
  const num = parseInt(val, 10);
  return isNaN(num) ? null : num;
}

function storeExpiresAt(expiresIn: number): void {
  const expiresAt = Date.now() + expiresIn * 1000;
  localStorage.setItem(EXPIRES_AT_KEY, String(expiresAt));
}

function clearExpiresAt(): void {
  localStorage.removeItem(EXPIRES_AT_KEY);
}

// ---- Token storage (access token ONLY; refresh token is in HttpOnly cookie) ----

export function storeTokens(tokens: TokenPair): void {
  localStorage.setItem(ACCESS_TOKEN_KEY, tokens.access_token);
}

export function clearTokens(): void {
  localStorage.removeItem(ACCESS_TOKEN_KEY);
  clearExpiresAt();
}

// ---- Validation ----

/**
 * Validates the public-permission guard before create/update.
 * Throws synchronously (status 422 mirrors the server) when violated.
 */
export function assertPublicAcknowledged(req: AccountRequest): void {
  if (req.permission === 'public' && req.public_acknowledged !== true) {
    throw new ApiError(422, 'public permission requires explicit acknowledgement');
  }
}

// ---- Error handling ----

async function parseError(response: Response): Promise<ApiError> {
  let message = `HTTP ${response.status}`;
  try {
    const body = await response.json();
    if (body && typeof body.error === 'string') message = body.error;
    else if (body && typeof body.message === 'string') message = body.message;
  } catch {
    /* body not JSON — keep status-based message */
  }
  return new ApiError(response.status, message);
}

// ---- ApiClient ----

export class ApiClient {
  /** Called when a refresh attempt ultimately fails (session expired). */
  onSessionExpired?: () => void;

  private refreshPromise: Promise<boolean> | null = null;
  private refreshTimerId: ReturnType<typeof setTimeout> | null = null;

  /**
   * Low-level fetch with credentials so HttpOnly cookies are always sent.
   */
  private async rawFetch(path: string, init: RequestInit = {}): Promise<Response> {
    return fetch(`${getApiBase()}${path}`, {
      ...init,
      credentials: 'include',
    });
  }

  /**
   * Call the refresh endpoint. The refresh token is read from the HttpOnly
   * cookie automatically (credentials:'include'). No refresh_token field is
   * sent in the body — the cookie carries it. The response includes a new
   * access token in the JSON body (and rotates the cookie).
   */
  private async refreshAccessToken(): Promise<boolean> {
    try {
      const response = await this.rawFetch('/auth/refresh', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: '{}',
      });
      if (!response.ok) {
        clearTokens();
        this.stopProactiveRefresh();
        return false;
      }
      const tokens = (await response.json()) as TokenPair;
      storeTokens(tokens);
      storeExpiresAt(tokens.expires_in);
      this.scheduleProactiveRefresh();
      return true;
    } catch {
      clearTokens();
      this.stopProactiveRefresh();
      return false;
    }
  }

  /** Serialized refresh — concurrent 401s share one refresh round-trip. */
  private async tryRefresh(): Promise<boolean> {
    if (!this.refreshPromise) {
      this.refreshPromise = this.refreshAccessToken().finally(() => {
        this.refreshPromise = null;
      });
    }
    return this.refreshPromise;
  }

  /**
   * Start the proactive token refresh timer. Safe to call when a timer is
   * already running (it will be rescheduled).  Called by AuthContext on mount
   * when a stored access token already exists.
   */
  startProactiveRefresh(): void {
    this.scheduleProactiveRefresh();
  }

  /** Cancel the proactive refresh timer.  Idempotent. */
  stopProactiveRefresh(): void {
    if (this.refreshTimerId !== null) {
      clearTimeout(this.refreshTimerId);
      this.refreshTimerId = null;
    }
  }

  /** (Re)schedule the next proactive refresh based on stored expires_at. */
  private scheduleProactiveRefresh(): void {
    this.stopProactiveRefresh();
    const expiresAt = getExpiresAt();
    if (!expiresAt) return;
    const delay = Math.max(
      0,
      expiresAt - Date.now() - REFRESH_LEAD_SECONDS * 1000,
    );
    this.refreshTimerId = setTimeout(() => {
      void this.performProactiveRefresh();
    }, delay);
  }

  /** Callback fired by the refresh timer. */
  private async performProactiveRefresh(): Promise<void> {
    const ok = await this.refreshAccessToken();
    if (!ok) {
      this.onSessionExpired?.();
    }
  }

  /** Authenticated request with one silent 401 → refresh → retry cycle. */
  async request<T>(path: string, init: RequestInit = {}, retry = true): Promise<T> {
    const headers = new Headers(init.headers);
    const token = getAccessToken();
    if (token) headers.set('Authorization', `Bearer ${token}`);
    if (init.body && !headers.has('Content-Type')) {
      headers.set('Content-Type', 'application/json');
    }

    const response = await this.rawFetch(path, { ...init, headers });

    if (response.status === 401 && retry) {
      const refreshed = await this.tryRefresh();
      if (refreshed) {
        return this.request<T>(path, init, false);
      }
      this.onSessionExpired?.();
      throw new ApiError(401, 'session expired');
    }

    if (!response.ok) throw await parseError(response);
    if (response.status === 204) return undefined as T;
    return (await response.json()) as T;
  }

  // ---- Endpoints (authoritative contract) ----

  async health(): Promise<HealthResponse> {
    const response = await this.rawFetch('/health');
    if (!response.ok) throw await parseError(response);
    return (await response.json()) as HealthResponse;
  }

  async login(username: string, password: string): Promise<TokenPair> {
    const response = await this.rawFetch('/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username, password }),
    });
    if (!response.ok) throw await parseError(response);
    const tokens = (await response.json()) as TokenPair;
    storeTokens(tokens);
    storeExpiresAt(tokens.expires_in);
    this.scheduleProactiveRefresh();
    return tokens;
  }

  /**
   * Log out: clear local access token, stop proactive refresh, and call
   * the server to revoke the refresh token + clear the HttpOnly cookie.
   * Server call is fire-and-forget — local state is cleared immediately.
   */
  async logout(): Promise<void> {
    const token = getAccessToken();
    clearTokens();
    this.stopProactiveRefresh();
    // Fire-and-forget server-side logout to clear the cookie and revoke.
    if (token) {
      try {
        const headers = new Headers();
        headers.set('Authorization', `Bearer ${token}`);
        headers.set('Content-Type', 'application/json');
        // Send empty body — the refresh token is read from the cookie.
        await this.rawFetch('/auth/logout', {
          method: 'POST',
          headers,
          body: '{}',
        });
      } catch {
        // Server logout is best-effort; local state is already cleared.
      }
    }
  }

  async me(): Promise<AdminIdentity> {
    return this.request<AdminIdentity>('/auth/me');
  }

  async listAccounts(): Promise<Account[]> {
    return this.request<Account[]>('/accounts');
  }

  async getAccount(username: string): Promise<Account> {
    return this.request<Account>(`/accounts/${encodeURIComponent(username)}`);
  }

  async createAccount(req: AccountRequest): Promise<Account> {
    assertPublicAcknowledged(req);
    return this.request<Account>('/accounts', {
      method: 'POST',
      body: JSON.stringify(req),
    });
  }

  async updateAccount(username: string, req: AccountRequest): Promise<Account> {
    assertPublicAcknowledged(req);
    return this.request<Account>(`/accounts/${encodeURIComponent(username)}`, {
      method: 'PUT',
      body: JSON.stringify(req),
    });
  }

  async deleteAccount(username: string): Promise<void> {
    return this.request<void>(`/accounts/${encodeURIComponent(username)}`, {
      method: 'DELETE',
    });
  }

  async sync(): Promise<SyncResult> {
    return this.request<SyncResult>('/sync', { method: 'POST' });
  }
}

export const apiClient = new ApiClient();
