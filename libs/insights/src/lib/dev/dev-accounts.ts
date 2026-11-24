/**
 * TEST HARNESS ONLY (Team 4). Delete when Team 1's real login is merged.
 *
 * The placeholder login lets you type "customer" or "admin" with no password.
 * Behind the scenes (live mode) it signs in to YOUR Supabase project with two
 * throw-away demo accounts, because the database rules (RLS + triggers) need a
 * real signed-in user. Create these two users in your project with this same
 * password (Authentication -> Add user, tick "Auto Confirm").
 * Never use these accounts or this password on a real project.
 */
export const DEV_PASSWORD = 'KitaFix-Dev-2026';

export const DEV_ACCOUNTS = {
  customer: 'customer@kitafix.test',
  admin: 'admin@kitafix.test',
} as const;

export type DevRole = keyof typeof DEV_ACCOUNTS;
