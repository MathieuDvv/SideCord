'use strict';

const {
  sidebarBounds,
  hiddenBounds,
  containsPoint,
  isEdgeExposed
} = require('./panel-geometry');

class PanelController {
  constructor({
    BrowserWindow, screen, settings, createWindow, onVisibilityChanged,
    additionalHoverBounds, automaticBehaviorSuppressed
  }) {
    this.BrowserWindow = BrowserWindow;
    this.screen = screen;
    this.settings = settings;
    this.createWindow = createWindow;
    this.onVisibilityChanged = onVisibilityChanged;
    this.additionalHoverBounds = additionalHoverBounds || (() => []);
    this.automaticBehaviorSuppressed = automaticBehaviorSuppressed || (() => false);
    this.window = null;
    this.visible = false;
    this.maximized = false;
    this.activeDisplayId = null;
    this.edgeContact = null;
    this.retractionStartedAt = null;
    this.animationGeneration = 0;
    this.timer = null;
    this.persistResizeTimer = null;
  }

  start() {
    if (!this.window) this.#installWindow(this.createWindow());
    if (!this.timer) this.timer = setInterval(() => this.#samplePointer(), 50);
  }

  stop() {
    if (this.timer) clearInterval(this.timer);
    if (this.persistResizeTimer) clearTimeout(this.persistResizeTimer);
    this.timer = null;
    this.persistResizeTimer = null;
  }

  #installWindow(window) {
    this.window = window;
    window.on('resize', () => {
      if (!this.visible || this.maximized) return;
      if (this.persistResizeTimer) clearTimeout(this.persistResizeTimer);
      this.persistResizeTimer = setTimeout(() => {
        const display = this.#activeDisplay();
        if (!display || !this.window || this.window.isDestroyed()) return;
        this.settings.setWidthForDisplay(display.id, this.window.getBounds().width);
      }, 250);
    });
    window.on('closed', () => {
      this.window = null;
      this.visible = false;
    });
  }

  toggle(activate = true) {
    if (this.visible) this.retract();
    else this.reveal(null, activate);
  }

  reveal(display = null, activate = true) {
    if (!this.window || this.window.isDestroyed()) this.#installWindow(this.createWindow());
    const targetDisplay = display || this.screen.getDisplayNearestPoint(this.screen.getCursorScreenPoint());
    this.activeDisplayId = targetDisplay.id;
    this.maximized = false;
    const target = this.#normalBounds(targetDisplay);
    const hidden = hiddenBounds(target, targetDisplay.bounds, this.settings.value.sidebarEdge);
    this.animationGeneration += 1;
    if (!this.visible) {
      this.window.setBounds(hidden, false);
      this.window.setOpacity(0);
      this.window.showInactive();
    }
    this.visible = true;
    this.retractionStartedAt = null;
    this.#animate(target, 1);
    if (activate) {
      this.window.show();
      this.window.focus();
    }
    this.onVisibilityChanged?.(true);
  }

  retract() {
    if (!this.visible || !this.window) return;
    const display = this.#activeDisplay();
    if (!display) return;
    const hidden = hiddenBounds(this.window.getBounds(), display.bounds, this.settings.value.sidebarEdge);
    this.visible = false;
    this.maximized = false;
    this.retractionStartedAt = null;
    this.#animate(hidden, 0, () => {
      if (!this.visible && this.window && !this.window.isDestroyed()) this.window.hide();
    });
    this.onVisibilityChanged?.(false);
  }

  togglePin() {
    this.settings.update({ isPinned: !this.settings.value.isPinned });
    if (this.settings.value.isPinned && !this.visible) this.reveal();
  }

  toggleMaximize() {
    if (!this.visible) this.reveal();
    const display = this.#activeDisplay();
    if (!display || !this.window) return;
    this.maximized = !this.maximized;
    this.#animate(this.maximized ? display.workArea : this.#normalBounds(display), 1);
  }

  reposition() {
    if (!this.visible || this.maximized || !this.window) return;
    const display = this.#activeDisplay();
    if (display) this.#animate(this.#normalBounds(display), 1);
  }

  #normalBounds(display) {
    return sidebarBounds(
      display.workArea,
      this.settings.value.sidebarEdge,
      this.settings.widthForDisplay(display.id),
      this.settings.value.sidebarInset
    );
  }

  #activeDisplay() {
    return this.screen.getAllDisplays().find((display) => display.id === this.activeDisplayId)
      || this.screen.getDisplayNearestPoint(this.screen.getCursorScreenPoint());
  }

  #samplePointer() {
    if (!this.window || this.window.isDestroyed()) return;
    const now = Date.now();
    const point = this.screen.getCursorScreenPoint();
    const current = this.settings.value;
    if (this.automaticBehaviorSuppressed()) {
      this.edgeContact = null;
      this.retractionStartedAt = null;
      return;
    }
    if (!this.visible) {
      if (!current.edgeHoverEnabled) {
        this.edgeContact = null;
        return;
      }
      const displays = this.screen.getAllDisplays();
      const candidate = displays.find((display) => {
        const vertical = point.y >= display.workArea.y
          && point.y <= display.workArea.y + display.workArea.height;
        const edgeX = current.sidebarEdge === 'left'
          ? display.bounds.x
          : display.bounds.x + display.bounds.width - 1;
        return vertical && Math.abs(point.x - edgeX) <= 3
          && isEdgeExposed(display, current.sidebarEdge, point.y, displays);
      });
      if (!candidate) {
        this.edgeContact = null;
      } else if (!this.edgeContact || this.edgeContact.id !== candidate.id) {
        this.edgeContact = { id: candidate.id, startedAt: now };
      } else if (now - this.edgeContact.startedAt >= current.hoverDwellDelay * 1000) {
        this.edgeContact = null;
        this.reveal(candidate, false);
      }
      return;
    }

    const relatedBounds = this.additionalHoverBounds().filter(Boolean);
    if (current.isPinned || this.maximized || this.window.isFocused()
      || containsPoint(this.window.getBounds(), point, 8)
      || relatedBounds.some((bounds) => containsPoint(bounds, point, 8))) {
      this.retractionStartedAt = null;
      return;
    }
    if (this.retractionStartedAt === null) this.retractionStartedAt = now;
    if (now - this.retractionStartedAt >= current.retractionDelay * 1000) this.retract();
  }

  #animate(target, opacity, completion) {
    if (!this.window || this.window.isDestroyed()) return;
    const generation = ++this.animationGeneration;
    const start = this.window.getBounds();
    const startOpacity = this.window.getOpacity();
    const startedAt = Date.now();
    const duration = 180;
    const tick = () => {
      if (generation !== this.animationGeneration || !this.window || this.window.isDestroyed()) return;
      const progress = Math.min(1, (Date.now() - startedAt) / duration);
      const eased = 1 - Math.pow(1 - progress, 3);
      const value = (from, to) => Math.round(from + (to - from) * eased);
      this.window.setBounds({
        x: value(start.x, target.x), y: value(start.y, target.y),
        width: value(start.width, target.width), height: value(start.height, target.height)
      }, false);
      this.window.setOpacity(startOpacity + (opacity - startOpacity) * eased);
      if (progress < 1) setTimeout(tick, 16);
      else completion?.();
    };
    tick();
  }
}

module.exports = { PanelController };
