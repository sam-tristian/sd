/**
 * ONE place for the Supabase URL and key (old build trap: the connection
 * string was copied into 7 files, 1 of them wrong).
 *
 * MODE 1 - offline demo (no internet):
 *   useMockData: true -> libs/booking uses the .ts placeholder data.
 *   npm start works anywhere, no Supabase needed.
 *
 * MODE 2 - real database (default, points at the shared hosted project):
 *   useMockData: false -> Supabase Auth + Postgres.
 *   Offline demo tip: flip it back to true (and reload) for the no-internet run.
 */
export const environment = {
  production: false,

  useMockData: false,

  /**
   * TEAM 4 TEST PROJECT (our own Supabase project, NOT the shared one).
   * Project URL: Supabase -> Connect (or Integrations -> Data API).
   * Key: Project Settings -> API Keys -> "Publishable key" (sb_publishable_...). Never the secret key.
   * Then set useMockData: false above. See docs/Team4_Test_Harness.md.
   */
  supabaseUrl: 'https://kiehobhklmfhaxkzkyjp.supabase.co',
  supabaseAnonKey: 'sb_publishable_LCvnfKQUns97pnrCC6QcJQ_kkorY96j',

  /** Branches shown in the booking form (availability is per location). */
  locations: ['Main Branch - Downtown', 'North Mall Branch'] as string[],

  /** The only hour slots the shop accepts. Keep in sync with docs/Booking_Rule.md. */
  slotTimes: ['09:00', '10:00', '11:00', '13:00', '14:00', '15:00', '16:00', '17:00'] as string[],

  currency: '\u20B1',
};
