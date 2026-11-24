import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { DevSessionService } from './dev-session.service';

/** TEST HARNESS ONLY. Customer pages: signed out -> login, admin -> admin side. */
export const devCustomerGuard: CanActivateFn = async () => {
  const session = inject(DevSessionService);
  const router = inject(Router);
  const role = await session.currentRole();
  if (!role) return router.createUrlTree(['/dev-login']);
  if (role === 'admin') return router.createUrlTree(['/admin']);
  return true;
};

/** TEST HARNESS ONLY. Admin pages: signed out -> login, customer -> customer side. */
export const devAdminGuard: CanActivateFn = async () => {
  const session = inject(DevSessionService);
  const router = inject(Router);
  const role = await session.currentRole();
  if (!role) return router.createUrlTree(['/dev-login']);
  if (role === 'customer') return router.createUrlTree(['/tabs']);
  return true;
};
