'use strict';

const path = require('node:path');
const { onboardingCompanionBounds, RAIL_WIDTH, RAIL_GAP } = require('./panel-geometry');

class OnboardingController {
  constructor({ BrowserWindow, screen, panel, settings, onSettingsPatch, onComplete, onGlow }) {
    this.BrowserWindow = BrowserWindow;
    this.screen = screen;
    this.panel = panel;
    this.settings = settings;
    this.onSettingsPatch = onSettingsPatch;
    this.onComplete = onComplete;
    this.onGlow = onGlow;
    this.stage = null;
    this.companion = null;
    this.display = null;
    this.phase = 'completed';
    this.step = 0;
    this.timer = null;
    this.generation = 0;
  }

  isActive() {
    return ['introductoryGlow', 'signIn', 'configuration', 'finishing'].includes(this.phase);
  }

  owns(contents) {
    return contents === this.stage?.webContents || contents === this.companion?.webContents;
  }

  start() {
    if (this.isActive()) return;
    this.generation += 1;
    this.display = this.screen.getDisplayNearestPoint(this.screen.getCursorScreenPoint());
    this.phase = 'introductoryGlow';
    this.step = 0;
    this.#ensureWindows();
    this.stage.setBounds(this.display.bounds, false);
    this.stage.show();
    this.stage.focus();
    this.#sendState();
    this.panel.retract();
    this.onGlow(true, this.display);
    const generation = this.generation;
    this.timer = setTimeout(() => {
      if (generation !== this.generation) return;
      this.panel.reveal(this.display, true);
      this.phase = 'signIn';
      this.#sendState();
      if (this.#isAuthenticated(this.panel.window?.webContents.getURL())) {
        setTimeout(() => {
          if (generation === this.generation && this.phase === 'signIn') this.showConfiguration();
        }, 350);
      }
    }, 850);
  }

  navigationChanged(url) {
    if (this.phase === 'signIn' && this.#isAuthenticated(url)) this.showConfiguration();
  }

  handleAction(action) {
    if (action === 'skip' && this.phase === 'signIn') this.showConfiguration();
    else if (action === 'backdrop' && this.phase === 'configuration') this.finish();
    else if (action === 'back' && this.phase === 'configuration' && this.step > 0) {
      this.step -= 1; this.#sendState(-1);
    } else if (action === 'next' && this.phase === 'configuration') {
      if (this.step >= 3) this.finish();
      else { this.step += 1; this.#sendState(1); }
    } else if (action === 'finish' && this.phase === 'configuration') this.finish();
  }

  updateSetting(key, value) {
    if (this.phase !== 'configuration') return;
    const allowed = new Set([
      'sidebarEdge', 'edgeHoverEnabled', 'discordLayoutMode', 'floatingRailEnabled',
      'visualTheme', 'themeAccent', 'notificationGlowEnabled', 'launchAtLoginEnabled'
    ]);
    if (!allowed.has(key)) return;
    this.onSettingsPatch({ [key]: value });
    this.reposition();
    this.#sendState();
  }

  settingsDidChange() {
    if (!this.isActive()) return;
    this.reposition();
    this.#sendState();
  }

  showConfiguration() {
    if (this.phase !== 'signIn') return;
    this.phase = 'configuration';
    this.step = 0;
    this.#sendState(1);
    const target = this.#companionBounds();
    const entrance = {
      ...target,
      x: target.x + (this.settings.value.sidebarEdge === 'right' ? 34 : -34)
    };
    this.companion.setBounds(entrance, false);
    this.companion.setOpacity(0);
    this.companion.show();
    this.companion.focus();
    this.#animateCompanion(target);
  }

  reposition() {
    if (this.phase !== 'configuration' || !this.companion?.isVisible()) return;
    this.companion.setBounds(this.#companionBounds(), true);
  }

  finish() {
    if (this.phase !== 'configuration' && this.phase !== 'signIn') return;
    this.phase = 'finishing';
    this.generation += 1;
    if (this.timer) clearTimeout(this.timer);
    this.timer = null;
    this.companion?.hide();
    this.stage?.hide();
    this.onComplete();
    this.phase = 'completed';
  }

  companionBounds() {
    return this.companion?.isVisible() ? this.companion.getBounds() : null;
  }

  #ensureWindows() {
    if (!this.stage || this.stage.isDestroyed()) {
      this.stage = new this.BrowserWindow({
        show: false, frame: false, transparent: true, backgroundColor: '#00000000',
        alwaysOnTop: true, skipTaskbar: true, resizable: false, movable: false,
        minimizable: false, maximizable: false, fullscreenable: false,
        webPreferences: {
          preload: path.join(__dirname, 'onboarding-stage-preload.js'),
          sandbox: true, contextIsolation: true, nodeIntegration: false
        }
      });
      this.stage.setAlwaysOnTop(true, 'floating');
      this.stage.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
      this.stage.loadFile(path.join(__dirname, '..', 'renderer', 'onboarding-stage.html'));
    }
    if (!this.companion || this.companion.isDestroyed()) {
      this.companion = new this.BrowserWindow({
        show: false, width: 430, height: 650, minWidth: 360, minHeight: 480,
        frame: false, transparent: true, backgroundColor: '#00000000',
        alwaysOnTop: true, skipTaskbar: true, resizable: false, movable: false,
        minimizable: false, maximizable: false, fullscreenable: false,
        webPreferences: {
          preload: path.join(__dirname, 'onboarding-preload.js'),
          sandbox: true, contextIsolation: true, nodeIntegration: false
        }
      });
      this.companion.setAlwaysOnTop(true, 'pop-up-menu');
      this.companion.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
      this.companion.loadFile(path.join(__dirname, '..', 'renderer', 'onboarding.html'));
    }
  }

  #sendState(direction = 1) {
    const value = { phase: this.phase, step: this.step, direction, settings: this.settings.value };
    for (const window of [this.stage, this.companion]) {
      if (window && !window.isDestroyed() && !window.webContents.isLoadingMainFrame()) {
        window.webContents.send('sidecord:onboarding-state', value);
      }
    }
  }

  #companionBounds() {
    const sidebar = this.panel.window.getBounds();
    const detachedRail = this.settings.value.floatingRailEnabled
      && this.settings.value.discordLayoutMode !== 'full';
    const reference = detachedRail
      ? {
          ...sidebar,
          x: this.settings.value.sidebarEdge === 'right'
            ? sidebar.x - RAIL_WIDTH - RAIL_GAP : sidebar.x,
          width: sidebar.width + RAIL_WIDTH + RAIL_GAP
        }
      : sidebar;
    return onboardingCompanionBounds(
      reference, this.display.workArea,
      this.settings.value.sidebarEdge
    );
  }

  #animateCompanion(target) {
    const generation = this.generation;
    const start = this.companion.getBounds();
    const startedAt = Date.now();
    const tick = () => {
      if (generation !== this.generation || !this.companion?.isVisible()) return;
      const progress = Math.min(1, (Date.now() - startedAt) / 460);
      const eased = 1 - Math.pow(1 - progress, 3);
      this.companion.setBounds({
        x: Math.round(start.x + (target.x - start.x) * eased),
        y: Math.round(start.y + (target.y - start.y) * eased),
        width: target.width, height: target.height
      }, false);
      this.companion.setOpacity(eased);
      if (progress < 1) setTimeout(tick, 16);
    };
    tick();
  }

  #isAuthenticated(rawUrl) {
    try { return new URL(rawUrl).pathname.toLowerCase().startsWith('/channels/'); }
    catch { return false; }
  }
}

module.exports = { OnboardingController };
