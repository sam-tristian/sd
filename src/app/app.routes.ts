import { Routes } from '@angular/router';
import { devAdminGuard, devCustomerGuard } from '@kitafix/insights';


export const routes: Routes = [
  {
    path: 'tabs',
    canActivate: [devCustomerGuard],
    loadComponent: () => import('./tabs/tabs.page').then((m) => m.TabsPage),
    children: [
      {
        path: '',
        loadChildren: () => import('@kitafix/booking').then((m) => m.BOOKING_ROUTES),
      },
      {
        path: '',
        loadChildren: () => import('@kitafix/insights').then((m) => m.INSIGHTS_ROUTES),
      },
    ],
  },
  {
    path: 'admin',
    canActivate: [devAdminGuard],
    loadChildren: () => import('@kitafix/insights').then((m) => m.INSIGHTS_STAFF_ROUTES),
  },
  {
    path: 'dev-login',
    loadComponent: () => import('./shared/session/dev-login.page').then((m) => m.DevLoginPage),
  },
  { path: '', redirectTo: 'tabs', pathMatch: 'full' },
  { path: '**', redirectTo: 'tabs' },
];