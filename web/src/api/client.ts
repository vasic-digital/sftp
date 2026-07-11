/**
 * SFTP Admin API client.
 *
 * - Base URL: VITE_API_BASE_URL env with a sane default; overridable per
 *   browser via localStorage (Settings screen).
 * - Auth: Bearer access token + one silent refresh on 401, then retry once.
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
const REFRESH_TOKEN_KEY = 'sftp.refresh_token';
const API_BASE_OVERRIDE_KEY = 'sftp.api_base_override';

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

export function getAccessToken(): string | null {
  return localStorage.getItem(ACCESS_TOKEN_KEY);
}

export function getRefreshToken(): string | null {
  return localStorage.getItem(REFRESH_TOKEN_KEY);
}

export function storeTokens(tokens: TokenPair): void {
  localStorage.setItem(ACCESS_TOKEN_KEY, tokens.access_token);
  localStorage.setItem(REFRESH_TOKEN_KEY, tokens.refresh_token);
}

export function clearTokens(): void {
  localStorage.removeItem(ACCESS_TOKEN_KEY);
  localStorage.removeItem(REFRESH_TOKEN_KEY);
}

export function isAuthenticated(): boolean {
  return getAccessToken() !== null;
}

/**
 * Validates the public-permission guard before create/update.
 * Throws synchronously (status 422 mirrors the server) when violated.
 */
export function assertPublicAcknowledged(req: AccountRequest): void {
  if (req.permission === 'public' && req.public_acknowledged !== true) {
    throw new ApiError(422, 'public permission requires explicit acknowledgement');
  }
}

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

export class ApiClient {
  /** Called when a refresh attempt ultimately fails (session expired). */
  onSessionExpired?: () => void;

  private refreshPromise: Promise<boolean> | null = null;

  private async rawFetch(path: string, init: RequestInit = {}): Promise<Response> {
    return fetch(`${getApiBase()}${path}`, init);
  }

  private async refreshAccessToken(): Promise<boolean> {
    const refreshToken = getRefreshToken();
    if (!refreshToken) return false;
    try {
      const response = await this.rawFetch('/auth/refresh', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ refresh_token: refreshToken }),
      });
      if (!response.ok) {
        clearTokens();
        return false;
      }
      const tokens = (await response.json()) as TokenPair;
      storeTokens(tokens);
      return true;
    } catch {
      clearTokens();
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
    return tokens;
  }

  logout(): void {
    clearTokens();
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
