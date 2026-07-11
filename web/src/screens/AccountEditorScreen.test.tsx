import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { storeTokens } from '../api/client';
import { AccountEditorScreen } from './AccountEditorScreen';

const TOKENS = {
  access_token: 'a',
  refresh_token: 'r',
  token_type: 'Bearer',
  expires_in: 3600,
};

function renderEditor(path = '/accounts/new') {
  return render(
    <MemoryRouter initialEntries={[path]}>
      <Routes>
        <Route path="/accounts/new" element={<AccountEditorScreen />} />
        <Route path="/accounts/:username/edit" element={<AccountEditorScreen />} />
      </Routes>
    </MemoryRouter>,
  );
}

describe('AccountEditorScreen', () => {
  beforeEach(() => {
    localStorage.clear();
    storeTokens(TOKENS);
    vi.stubGlobal('fetch', vi.fn());
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('defaults permission to read_write and never public', () => {
    renderEditor();
    const select = screen.getByLabelText('Permission') as HTMLSelectElement;
    expect(select.value).toBe('read_write');
  });

  it('shows the acknowledgement checkbox only when public is selected', async () => {
    const user = userEvent.setup();
    renderEditor();
    expect(screen.queryByLabelText(/explicitly acknowledge/i)).toBeNull();
    await user.selectOptions(screen.getByLabelText('Permission'), 'public');
    expect(screen.getByLabelText(/explicitly acknowledge/i)).toBeInTheDocument();
  });

  it('blocks submit of unacknowledged public access with the guard message', async () => {
    const user = userEvent.setup();
    renderEditor();
    await user.type(screen.getByLabelText('Username'), 'bob');
    await user.type(screen.getByLabelText('Password'), 'secret');
    await user.selectOptions(screen.getByLabelText('Permission'), 'public');

    const submit = screen.getByRole('button', { name: /create account/i });
    expect(submit).toBeDisabled();
    expect(fetch).not.toHaveBeenCalled();
  });

  it('sends public_acknowledged=true once acknowledged', async () => {
    const user = userEvent.setup();
    vi.mocked(fetch).mockResolvedValue(
      new Response(
        JSON.stringify({
          username: 'bob',
          permission: 'public',
          uid: null,
          gid: null,
          home_dir: '',
          enabled: true,
          created_at: '',
          updated_at: '',
        }),
        { status: 200, headers: { 'Content-Type': 'application/json' } },
      ),
    );
    renderEditor();
    await user.type(screen.getByLabelText('Username'), 'bob');
    await user.type(screen.getByLabelText('Password'), 'secret');
    await user.selectOptions(screen.getByLabelText('Permission'), 'public');
    await user.click(screen.getByLabelText(/explicitly acknowledge/i));
    await user.click(screen.getByRole('button', { name: /create account/i }));

    await waitFor(() => expect(fetch).toHaveBeenCalled());
    const body = JSON.parse(vi.mocked(fetch).mock.calls[0][1]?.body as string);
    expect(body.permission).toBe('public');
    expect(body.public_acknowledged).toBe(true);
  });

  it('loads an existing account in edit mode', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(
      new Response(
        JSON.stringify({
          username: 'alice',
          permission: 'read_only',
          uid: 1001,
          gid: 1001,
          home_dir: '/srv/sftp/alice',
          enabled: true,
          created_at: '',
          updated_at: '',
        }),
        { status: 200, headers: { 'Content-Type': 'application/json' } },
      ),
    );
    renderEditor('/accounts/alice/edit');
    await waitFor(() =>
      expect((screen.getByLabelText('Permission') as HTMLSelectElement).value).toBe(
        'read_only',
      ),
    );
    expect((screen.getByLabelText('Username') as HTMLInputElement).disabled).toBe(true);
  });
});
