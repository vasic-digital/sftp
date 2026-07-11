import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import {
  ApiClient,
  assertPublicAcknowledged,
  clearTokens,
  getAccessToken,
  storeTokens,
} from './client';
import { ApiError, TokenPair } from './types';

const TOKENS: TokenPair = {
  access_token: 'access-1',
  refresh_token: 'refresh-1',
  token_type: 'Bearer',
  expires_in: 3600,
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function storeAccessExpiry(): void {
  const expiresAt = Date.now() + TOKENS.expires_in * 1000;
  localStorage.setItem('sftp.expires_at', String(expiresAt));
}

describe('ApiClient', () => {
  let client: ApiClient;

  beforeEach(() => {
    localStorage.clear();
    client = new ApiClient();
    vi.stubGlobal('fetch', vi.fn());
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    clearTokens();
  });

  it('login stores access token (refresh token is HttpOnly cookie)', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(jsonResponse(TOKENS));
    await client.login('admin', 'secret');
    expect(getAccessToken()).toBe('access-1');
    // refresh token is no longer in localStorage — it lives in an HttpOnly cookie
  });

  it('sends Authorization header with stored access token', async () => {
    storeTokens(TOKENS);
    vi.mocked(fetch).mockResolvedValueOnce(jsonResponse([]));
    await client.listAccounts();
    const headers = vi.mocked(fetch).mock.calls[0][1]?.headers as Headers;
    expect(headers.get('Authorization')).toBe('Bearer access-1');
  });

  it('sends credentials:include on all requests', async () => {
    storeTokens(TOKENS);
    vi.mocked(fetch).mockResolvedValueOnce(jsonResponse([]));
    await client.listAccounts();
    const init = vi.mocked(fetch).mock.calls[0][1] as RequestInit;
    expect(init.credentials).toBe('include');
  });

  it('on 401 performs one silent refresh then retries the request', async () => {
    storeTokens(TOKENS);
    storeAccessExpiry();
    const fetchMock = vi.mocked(fetch);
    fetchMock
      .mockResolvedValueOnce(jsonResponse({ error: 'expired' }, 401))
      .mockResolvedValueOnce(
        jsonResponse({ ...TOKENS, access_token: 'access-2', refresh_token: 'refresh-2' }),
      )
      .mockResolvedValueOnce(jsonResponse([{ username: 'alice' }]));

    const accounts = await client.listAccounts();
    expect(accounts).toHaveLength(1);
    expect(getAccessToken()).toBe('access-2');
    expect(fetchMock).toHaveBeenCalledTimes(3);
    const retryHeaders = fetchMock.mock.calls[2][1]?.headers as Headers;
    expect(retryHeaders.get('Authorization')).toBe('Bearer access-2');
  });

  it('when refresh fails, clears session and notifies onSessionExpired', async () => {
    storeTokens(TOKENS);
    const expired = vi.fn();
    client.onSessionExpired = expired;
    vi.mocked(fetch)
      .mockResolvedValueOnce(jsonResponse({ error: 'expired' }, 401))
      .mockResolvedValueOnce(jsonResponse({ error: 'invalid refresh' }, 401));

    await expect(client.listAccounts()).rejects.toBeInstanceOf(ApiError);
    expect(expired).toHaveBeenCalledOnce();
    expect(getAccessToken()).toBeNull();
  });

  it('serializes concurrent 401s into a single refresh round-trip', async () => {
    storeTokens(TOKENS);
    const fetchMock = vi.mocked(fetch);
    fetchMock
      .mockResolvedValueOnce(jsonResponse({ error: 'expired' }, 401))
      .mockResolvedValueOnce(jsonResponse({ error: 'expired' }, 401))
      .mockResolvedValueOnce(
        jsonResponse({ ...TOKENS, access_token: 'access-2' }),
      )
      .mockResolvedValueOnce(jsonResponse([]))
      .mockResolvedValueOnce(jsonResponse([]));

    await Promise.all([client.listAccounts(), client.listAccounts()]);
    const refreshCalls = fetchMock.mock.calls.filter((c) =>
      String(c[0]).includes('/auth/refresh'),
    );
    expect(refreshCalls).toHaveLength(1);
  });

  it('public-ack guard throws 422 client-side when acknowledgement missing', () => {
    expect(() =>
      assertPublicAcknowledged({ username: 'x', permission: 'public' }),
    ).toThrowError(ApiError);
    expect(() =>
      assertPublicAcknowledged({
        username: 'x',
        permission: 'public',
        public_acknowledged: true,
      }),
    ).not.toThrow();
    expect(() =>
      assertPublicAcknowledged({ username: 'x', permission: 'read_write' }),
    ).not.toThrow();
  });

  it('createAccount blocks unacknowledged public permission before any fetch', async () => {
    storeTokens(TOKENS);
    await expect(
      client.createAccount({ username: 'x', permission: 'public' }),
    ).rejects.toMatchObject({ status: 422 });
    expect(fetch).not.toHaveBeenCalled();
  });

  it('parses account responses (never expects a password field)', async () => {
    storeTokens(TOKENS);
    vi.mocked(fetch).mockResolvedValueOnce(
      jsonResponse({
        username: 'alice',
        permission: 'read_write',
        uid: 1001,
        gid: 1001,
        home_dir: '/srv/sftp/alice',
        enabled: true,
        created_at: '2026-07-01T00:00:00Z',
        updated_at: '2026-07-01T00:00:00Z',
      }),
    );
    const acc = await client.getAccount('alice');
    expect(acc.username).toBe('alice');
    expect(acc).not.toHaveProperty('password');
  });

  it('delete returns undefined on 204', async () => {
    storeTokens(TOKENS);
    vi.mocked(fetch).mockResolvedValueOnce(new Response(null, { status: 204 }));
    await expect(client.deleteAccount('alice')).resolves.toBeUndefined();
  });

  it('logout clears access token and calls server', async () => {
    storeTokens(TOKENS);
    vi.mocked(fetch).mockResolvedValueOnce(jsonResponse({ message: 'logged out' }));
    await client.logout();
    expect(getAccessToken()).toBeNull();
    const logoutCall = vi.mocked(fetch).mock.calls.find((c) =>
      String(c[0]).includes('/auth/logout'),
    );
    expect(logoutCall).toBeDefined();
  });
});
