import { NavLink, Outlet, useNavigate } from 'react-router-dom';
import { useAuth } from '../auth/AuthContext';
import { t } from '../i18n';

export function Layout() {
  const { logout } = useAuth();
  const navigate = useNavigate();

  return (
    <div className="app-shell">
      <header className="topbar">
        <span className="brand">{t('app.title')}</span>
        <nav>
          <NavLink to="/" end className={({ isActive }) => (isActive ? 'active' : '')}>
            {t('nav.dashboard')}
          </NavLink>
          <NavLink to="/accounts/new" className={({ isActive }) => (isActive ? 'active' : '')}>
            {t('nav.newAccount')}
          </NavLink>
          <NavLink to="/settings" className={({ isActive }) => (isActive ? 'active' : '')}>
            {t('nav.settings')}
          </NavLink>
        </nav>
        <button
          className="btn secondary"
          onClick={() => {
            logout();
            navigate('/login');
          }}
        >
          {t('nav.logout')}
        </button>
      </header>
      <main className="page">
        <Outlet />
      </main>
    </div>
  );
}
