import { Injectable, inject, signal } from '@angular/core';
import { Router } from '@angular/router';
import type { SupabaseClient } from '@supabase/supabase-js';
import { BOOKING_CONFIG, getSupabaseClient } from '@kitafix/booking';
import { DEV_ACCOUNTS, DEV_PASSWORD, DevRole } from './dev-accounts';

const KEY = 'kitafix.dev.role';

function stored(): DevRole | null {
  try {
    const v = sessionStorage.getItem(KEY);
    return v === 'customer' || v === 'admin' ? v : null;
  } catch {
    return null;
  }
}

/**
 * TEST HARNESS ONLY. Placeholder login / logout so Team 4 can open both the
 * customer side and the admin side before Team 1's login exists.
 *
 *  mock mode  (useMockData: true)  -> nothing leaves the browser.
 *  live mode  (useMockData: false) -> signs in to your own Supabase project with
 *                                     the demo account behind the typed word.
 */
@Injectable({ providedIn: 'root' })
export class DevSessionService {
  private readonly config = inject(BOOKING_CONFIG);
  private readonly router = inject(Router);
  private readonly live = !this.config.useMockData;

  readonly role = signal<DevRole | null>(this.live ? null : stored());
  readonly displayName = signal('');

  /** "customer" / "admin" (no password), or a real email + password in live mode. */
  async login(who: string, password = ''): Promise<DevRole> {
    const word = who.trim().toLowerCase();
    const typedRole = word === 'customer' || word === 'admin' ? (word as DevRole) : null;

    if (!this.live) {
      if (!typedRole) throw new Error('Type customer or admin.');
      this.set(typedRole, typedRole === 'admin' ? 'Demo Admin' : 'Alex Santos');
      return typedRole;
    }

    const email = typedRole ? DEV_ACCOUNTS[typedRole] : word;
    const pass = typedRole ? DEV_PASSWORD : password;
    if (!email || !pass) throw new Error('Type customer or admin.');

    const db = this.db();
    const { error } = await db.auth.signInWithPassword({ email, password: pass });
    if (error) {
      throw new Error(
        typedRole
          ? `Could not sign in the demo ${typedRole} (${error.message}). Create ${email} in your Supabase project with the dev password.`
          : error.message,
      );
    }
    const info = await this.readProfile(db);
    if (typedRole === 'admin' && info.role !== 'admin') {
      await db.auth.signOut();
      throw new Error('admin@kitafix.test exists but is not an admin yet. Run supabase/dev/02_roles_and_seed.sql.');
    }
    this.set(info.role, info.name);
    return info.role;
  }

  /** Used by the route guards. Restores the role after a page reload. */
  async currentRole(): Promise<DevRole | null> {
    if (!this.live) return this.role();
    const db = this.db();
    const { data } = await db.auth.getSession();
    if (!data.session) {
      this.forget();
      return null;
    }
    if (this.role()) return this.role();
    const info = await this.readProfile(db);
    this.set(info.role, info.name);
    return info.role;
  }

  async logout(): Promise<void> {
    try {
      if (this.live) await this.db().auth.signOut();
      sessionStorage.removeItem(KEY);
    } catch {
      /* ignore: we are leaving anyway */
    }
    this.role.set(null);
    this.displayName.set('');
    await this.router.navigateByUrl('/dev-login', { replaceUrl: true });
  }

  /** Drops the remembered role (the login screen calls this, so a signed-out app stays signed out). */
  forget(): void {
    try {
      sessionStorage.removeItem(KEY);
    } catch {
      /* ignore */
    }
    this.role.set(null);
    this.displayName.set('');
  }

  private set(role: DevRole, name: string): void {
    this.role.set(role);
    this.displayName.set(name);
    try {
      sessionStorage.setItem(KEY, role);
    } catch {
      /* private mode: the role stays in memory */
    }
  }

  private async readProfile(db: SupabaseClient): Promise<{ role: DevRole; name: string }> {
    const { data: auth } = await db.auth.getUser();
    const id = auth.user?.id;
    if (!id) throw new Error('You are not signed in.');
    const { data } = await db.from('profiles').select('role, full_name').eq('id', id).maybeSingle();
    const row = data as { role?: string; full_name?: string } | null;
    return { role: row?.role === 'admin' ? 'admin' : 'customer', name: row?.full_name ?? auth.user?.email ?? '' };
  }

  private db(): SupabaseClient {
    return getSupabaseClient(this.config.supabaseUrl, this.config.supabaseAnonKey) as unknown as SupabaseClient;
  }
}
