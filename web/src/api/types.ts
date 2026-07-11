/** API contract types — mirrors the Go/Gin backend exactly. */

export type Permission = 'read_only' | 'read_write' | 'public';

export interface Account {
  username: string;
  permission: Permission;
  uid: number | null;
  gid: number | null;
  home_dir: string;
  enabled: boolean;
  created_at: string;
  updated_at: string;
}

/** Request shape for create/update. Password is never returned by the API. */
export interface AccountRequest {
  username: string;
  password?: string;
  permission: Permission;
  public_acknowledged?: boolean;
  uid?: number | null;
  gid?: number | null;
  home_dir?: string;
  enabled?: boolean;
}

export interface TokenPair {
  access_token: string;
  refresh_token?: string;
  token_type: string;
  expires_in: number;
  refresh_expires_in?: number;
}

export interface HealthResponse {
  status: string;
  [key: string]: unknown;
}

export interface AdminIdentity {
  username: string;
  [key: string]: unknown;
}

export interface SyncResult {
  status?: string;
  synced?: number;
  message?: string;
  [key: string]: unknown;
}

export class ApiError extends Error {
  constructor(
    public readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = 'ApiError';
  }
}
