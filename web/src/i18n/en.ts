/**
 * English locale dictionary — English-first i18n (constitution §11.4.162).
 * All user-facing UI strings MUST resolve through this table; never hardcode
 * strings in JSX. Keys are dot-namespaced by surface.
 */
export const en = {
  'app.title': 'SFTP Admin',
  'app.tagline': 'Enterprise SFTP management console',

  'nav.dashboard': 'Dashboard',
  'nav.newAccount': 'New account',
  'nav.settings': 'Settings',
  'nav.logout': 'Sign out',

  'common.loading': 'Loading…',
  'common.save': 'Save',
  'common.cancel': 'Cancel',
  'common.delete': 'Delete',
  'common.edit': 'Edit',
  'common.confirm': 'Confirm',
  'common.back': 'Back',
  'common.error': 'Something went wrong',
  'common.retry': 'Retry',
  'common.yes': 'Yes',
  'common.no': 'No',
  'common.none': '—',

  'login.heading': 'Sign in',
  'login.username': 'Username',
  'login.password': 'Password',
  'login.submit': 'Sign in',
  'login.failed': 'Invalid credentials or server error.',
  'login.health.ok': 'Server online',
  'login.health.down': 'Server unreachable',
  'login.health.checking': 'Checking server…',

  'dashboard.heading': 'Accounts',
  'dashboard.count': '{count} account(s)',
  'dashboard.sync': 'Sync to server',
  'dashboard.syncing': 'Syncing…',
  'dashboard.sync.ok': 'Configuration synced to the SFTP server.',
  'dashboard.sync.failed': 'Sync failed.',
  'dashboard.empty': 'No accounts yet. Create one to get started.',
  'dashboard.deleteConfirm': 'Delete account "{username}"? This cannot be undone.',
  'dashboard.status.ok': 'Operational',
  'dashboard.status.unknown': 'Unknown',

  'table.username': 'Username',
  'table.permission': 'Permission',
  'table.uid': 'UID',
  'table.gid': 'GID',
  'table.homeDir': 'Home directory',
  'table.enabled': 'Enabled',
  'table.actions': 'Actions',
  'table.created': 'Created',

  'permission.read_only': 'Read only',
  'permission.read_write': 'Read / write',
  'permission.public': 'Public',

  'editor.new.heading': 'New account',
  'editor.edit.heading': 'Edit account "{username}"',
  'editor.username': 'Username',
  'editor.password': 'Password',
  'editor.password.hint.edit': 'Leave blank to keep the current password.',
  'editor.password.hint.new': 'Required for new accounts.',
  'editor.permission': 'Permission',
  'editor.homeDir': 'Home directory',
  'editor.uid': 'UID (optional)',
  'editor.gid': 'GID (optional)',
  'editor.enabled': 'Account enabled',
  'editor.publicWarning':
    'Public access grants unauthenticated read access. This is NEVER the default and must be explicitly acknowledged.',
  'editor.publicAck':
    'I understand and explicitly acknowledge the risks of public access for this account.',
  'editor.publicAck.required':
    'Public access requires explicit acknowledgement before it can be saved.',
  'editor.submit.new': 'Create account',
  'editor.submit.edit': 'Save changes',
  'editor.saved': 'Account saved.',
  'editor.failed': 'Could not save the account.',
  'editor.username.required': 'Username is required.',
  'editor.load.failed': 'Could not load the account.',

  'settings.heading': 'Settings',
  'settings.theme': 'Theme',
  'settings.theme.light': 'Light',
  'settings.theme.dark': 'Dark',
  'settings.theme.system': 'System',
  'settings.apiBase': 'API base URL',
  'settings.apiBase.hint': 'Overrides the built-in default for this browser only.',
  'settings.apiBase.saved': 'API base URL updated.',
  'settings.about': 'About',
  'settings.version': 'Web client version: {version}',
  'settings.apiDefault': 'Default API base: {base}',

  'auth.sessionExpired': 'Your session expired. Please sign in again.',
} as const;

export type I18nKey = keyof typeof en;
