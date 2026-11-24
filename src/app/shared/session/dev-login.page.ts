import { ChangeDetectionStrategy, Component, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { IonButton, IonContent, IonIcon, IonInput, IonNote, IonSpinner } from '@ionic/angular';
import { DevSessionService } from '@kitafix/insights';

/**
 * DEV ONLY. Team 1 owns the real Login screen.
 *
 * Test login for the module harness: type  customer  or  admin  (no password).
 * customer -> customer app (/tabs), admin -> admin side (/admin).
 * A real email + password still works in live mode (the password box appears
 * as soon as you type an "@").
 */
@Component({
  selector: 'app-dev-login',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [FormsModule, IonButton, IonContent, IonIcon, IonInput, IonNote, IonSpinner],
  templateUrl: './dev-login.page.html',
  styleUrl: './dev-login.page.scss',
})
export class DevLoginPage {
  private readonly router = inject(Router);
  private readonly session = inject(DevSessionService);

  constructor() {
    // Landing on the login screen means nobody is signed in (mock mode would otherwise remember the role).
    this.session.forget();
  }

  readonly loading = signal(false);
  readonly error = signal<string | null>(null);
  readonly showPassword = signal(false);
  readonly email = signal('');
  readonly password = signal('');
  readonly needsPassword = computed(() => this.email().includes('@'));

  togglePassword(): void {
    this.showPassword.update((visible) => !visible);
  }

  /** Forgot password / Sign up belong to Team 1's identity module. */
  teamOneOnly(): void {
    this.error.set('Forgot password and Sign up come with Team 1\u2019s Login screen.');
  }

  async signIn(): Promise<void> {
    if (!this.email().trim()) {
      this.error.set('Type customer or admin.');
      return;
    }
    this.loading.set(true);
    this.error.set(null);
    try {
      const role = await this.session.login(this.email(), this.password());
      await this.router.navigateByUrl(role === 'admin' ? '/admin' : '/tabs', { replaceUrl: true });
    } catch (caught) {
      this.error.set(caught instanceof Error ? caught.message : 'Sign in failed.');
    } finally {
      this.loading.set(false);
    }
  }
}
