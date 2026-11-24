import { InjectionToken } from '@angular/core';
import { Repair } from '../models/repair.model';

/**
 * EXTENSION POINT (added for Team 4's standalone testing; additive and safe to keep).
 *
 * Other modules can show an extra button under a repair on the Repairs page
 * without Team 2's page importing them (rule R6: no imports in that direction).
 * The host app registers actions with provideMulti: see provideTeam4RepairActions()
 * in @kitafix/insights. With nothing registered the Repairs page looks as before.
 */
export interface RepairExtraAction {
  id: string;
  label: string;
  /** Name of an ionicon already registered in src/app/icons.ts. */
  icon: string;
  color?: string;
  /** Show the button for this repair? */
  appliesTo(repair: Repair): boolean;
  /** Do the work. May return a short success message for the toast. */
  run(repair: Repair): Promise<string | void>;
}

export const REPAIR_EXTRA_ACTIONS = new InjectionToken<RepairExtraAction[]>('REPAIR_EXTRA_ACTIONS');
