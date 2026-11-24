import { ChangeDetectionStrategy, Component, computed, inject } from '@angular/core';
import { IonIcon, IonItem, IonLabel, IonList, IonPopover } from '@ionic/angular';
import { DevSessionService } from '../../dev/dev-session.service';

let nextId = 0;

/**
 * TEST HARNESS: the round account button at the top right of the admin screens
 * (same idea as the customer's avatar). Tap it -> "Sign out".
 * Team 1 replaces this with the real account menu.
 */
@Component({
  selector: 'app-insights-account-menu',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [IonIcon, IonItem, IonLabel, IonList, IonPopover],
  template: `
    <button [id]="triggerId" type="button" class="avatar" aria-label="Account menu">{{ initial() }}</button>
    <ion-popover [trigger]="triggerId" triggerAction="click" #menu>
      <ng-template>
        <ion-list lines="none">
          <ion-item button detail="false" (click)="menu.dismiss(); signOut()">
            <ion-icon slot="start" name="log-out-outline"></ion-icon>
            <ion-label>Sign out</ion-label>
          </ion-item>
        </ion-list>
      </ng-template>
    </ion-popover>
  `,
  styles: [
    `
      :host { display: inline-block; }
      .avatar {
        width: 40px;
        height: 40px;
        border-radius: 50%;
        display: grid;
        place-items: center;
        padding: 0;
        font: inherit;
        font-weight: 700;
        color: #fff;
        background: rgba(255, 255, 255, 0.22);
        border: 2px solid rgba(255, 255, 255, 0.85);
        cursor: pointer;
      }
    `,
  ],
})
export class AccountMenuComponent {
  private readonly session = inject(DevSessionService);
  readonly triggerId = `t4-account-${nextId++}`;
  readonly initial = computed(() => (this.session.displayName().charAt(0) || 'A').toUpperCase());

  signOut(): void {
    void this.session.logout();
  }
}
