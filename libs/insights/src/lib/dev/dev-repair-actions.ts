import { Provider, inject } from '@angular/core';
import { Router } from '@angular/router';
import type { SupabaseClient } from '@supabase/supabase-js';
import {
  BOOKING_CONFIG, REPAIR_EXTRA_ACTIONS, Repair, RepairExtraAction, getSupabaseClient, isActiveRepair, mockRepairsDb,
} from '@kitafix/booking';

/**
 * Buttons Team 4 adds under each repair on Team 2's Repairs page:
 *
 *   "Complete now"    (active repair)    TEST HARNESS ONLY. Finishes the repair so it
 *                                         can be reviewed, without waiting for Team 3's admin.
 *                                         live -> rpc dev_complete_my_repair
 *                                                 (supabase/dev/01_dev_complete_repair.sql)
 *                                         mock -> changes the in-memory placeholder row
 *   "Leave a review"  (completed repair) Opens /tabs/leave-review/<repair id>. Keep this one:
 *                                         it is the link Team 2 will add on integration.
 */
export function provideTeam4RepairActions(): Provider[] {
  return [
    {
      provide: REPAIR_EXTRA_ACTIONS,
      multi: true,
      useFactory: (): RepairExtraAction => {
        const config = inject(BOOKING_CONFIG);
        return {
          id: 'complete-now',
          label: 'Complete now (test)',
          icon: 'checkmark-done-outline',
          color: 'success',
          appliesTo: (repair: Repair) => isActiveRepair(repair),
          run: async (repair: Repair) => {
            if (config.useMockData) {
              const rows = (mockRepairsDb as unknown as { rows: Repair[] }).rows;
              const row = rows.find((r) => r.id === repair.id);
              if (!row) throw new Error('Repair not found.');
              row.status = 'completed';
              return 'Repair completed. Find it under History to leave a review.';
            }
            const db = getSupabaseClient(config.supabaseUrl, config.supabaseAnonKey) as unknown as SupabaseClient;
            const { error } = await db.rpc('dev_complete_my_repair', { p_repair_id: repair.id });
            if (error) throw new Error(error.message);
            return 'Repair completed. Find it under History to leave a review.';
          },
        };
      },
    },
    {
      provide: REPAIR_EXTRA_ACTIONS,
      multi: true,
      useFactory: (): RepairExtraAction => {
        const router = inject(Router);
        return {
          id: 'leave-review',
          label: 'Leave a review',
          icon: 'create-outline',
          appliesTo: (repair: Repair) => repair.status === 'completed',
          run: async (repair: Repair) => {
            await router.navigate(['/tabs/leave-review', repair.id]);
          },
        };
      },
    },
  ];
}
