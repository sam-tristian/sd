# Team 4 test harness (run our module alone, on our own Supabase project)

Everything here is for **testing Feedback & Insights before integration**. The
"dev" pieces are marked `TEST HARNESS ONLY` and are deleted at merge.

## What you get

The app keeps the original pages (customer: Home / Book / Repairs, admin: Overview / Insights). Nothing extra was added as a page.

| Side | How to enter | What you can do |
| --- | --- | --- |
| Customer | log in as `customer` | Book as usual. On the **Repairs** tab every active repair has a **Complete now (test)** button. After it, the repair moves to **History** and shows **Leave a review** -> rating 1-5, comment <= 200, edit/delete within 1 hour. |
| Admin | log in as `admin` | Overview, Insights (Reviews: search, filter, reply once, delete with confirm; Reports: status, rating stars, technician performance). |

Login page: type `customer` or `admin`, no password. **Sign out**: tap the round account button at the top right (customer Home screen, admin Overview and Insights).

How the Repairs-page buttons work without breaking the rules: `libs/booking` has one small, additive extension point
(`extensions/repair-extra-actions.ts`: an injection token + a loop in `my-repairs.page`). Team 4 registers the two buttons
in `libs/insights/src/lib/dev/dev-repair-actions.ts`. With nothing registered the Repairs page is identical to before.
Tell Team 2 about this small change (rule R10).

## One-time setup on YOUR Supabase project

1. **SQL Editor**: paste and run `supabase/dev/00_setup_all.sql` (the repo migrations 0001-0090 in order).
2. **SQL Editor**: paste and run `supabase/dev/01_dev_complete_repair.sql` (powers "Complete now").
3. **Authentication -> Users -> Add user** (tick *Auto Confirm User*), password = `DEV_PASSWORD` from
   `libs/insights/src/lib/dev/dev-accounts.ts` (default `KitaFix-Dev-2026`):
   `customer@kitafix.test`, `marcos.tech@kitafix.test`, `dina.tech@kitafix.test`, `admin@kitafix.test`.
4. **SQL Editor**: run `supabase/dev/02_roles_and_seed.sql` (roles, services, technicians, 2 sample bookings).
5. `src/environments/environment.ts`: paste the **publishable key**, set `useMockData: false`.
6. `npm ci` then `npm start`, open http://localhost:4200, type `customer`.

Offline / no database: leave `useMockData: true`. The login, Complete now, preview and review page still work
(in memory, resets on refresh); the admin side shows sample data.

## Why the login still talks to Supabase in live mode

The database rules (RLS + the 1-hour triggers) need a real signed-in user (`auth.uid()`).
So typing `customer` signs in the demo customer account behind the scenes. No password is typed, but the
account exists in your project. A login that never touches Supabase cannot satisfy those rules - that is only possible in mock mode.

## Why "Complete now" needs its own SQL

A customer is not allowed to complete a repair (Team 2's guard trigger, Team 3 owns the status machine).
`dev_complete_my_repair` is a test-only shortcut. It must never be added to `supabase/migrations/`.

## Before merging into the group repo

- Delete `libs/insights/src/lib/dev/` (the "Leave a review" button moves to Team 2's repair card as a plain link to
  `/tabs/leave-review/<repair id>`; drop "Complete now"), the admin account button (`account-menu.component.ts`), `supabase/dev/`, and restore the shared login/guards.
- Tell Team 2 about the `extensions/repair-extra-actions.ts` addition (note R10), or ask them to remove it once the link is native.
- Restore the shared project URL/key in `environment.ts`.
