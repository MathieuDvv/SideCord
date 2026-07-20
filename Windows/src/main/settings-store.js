'use strict';

const fs = require('node:fs');
const path = require('node:path');

const DEFAULTS = Object.freeze({
  sidebarEdge: 'right',
  edgeHoverEnabled: true,
  notificationGlowEnabled: true,
  attentionGlowColor: 'followTheme',
  attentionGlowStrength: 'normal',
  incomingCallCardEnabled: true,
  hoverDwellDelay: 0.25,
  retractionDelay: 0.7,
  sidebarWidth: 420,
  sidebarInset: 16,
  displayWidths: {},
  cssPreset: 'compact',
  discordLayoutMode: 'full',
  customDiscordLayoutOptions: {
    navigationPresentation: 'docked',
    composerMode: 'full',
    hideMemberList: false,
    hideAccountDock: false,
    simplifyHeader: false,
    compactMedia: false,
    reduceMotion: false
  },
  floatingRailEnabled: true,
  visualTheme: 'systemGlass',
  themeAccent: 'automatic',
  themeIntensity: 1,
  themeColorScheme: 'system',
  customCSS: '',
  customCSSEnabled: false,
  launchAtLoginEnabled: false,
  shortcut: 'Alt+D',
  navigationShortcut: 'Alt+Shift+D',
  isPinned: false,
  onboardingCompleted: false
});

const ENUMS = {
  sidebarEdge: ['left', 'right'],
  attentionGlowColor: ['followTheme', 'blurple', 'blue', 'purple', 'pink', 'green', 'orange', 'white'],
  attentionGlowStrength: ['subtle', 'normal', 'strong'],
  cssPreset: ['default', 'compact'],
  discordLayoutMode: ['full', 'focus', 'reader', 'custom'],
  visualTheme: ['systemGlass', 'discord', 'oled', 'soft'],
  themeAccent: ['automatic', 'blurple', 'blue', 'purple', 'pink', 'green', 'orange', 'white'],
  themeColorScheme: ['system', 'light', 'dark']
};

const BOOLEAN_KEYS = [
  'edgeHoverEnabled', 'notificationGlowEnabled', 'incomingCallCardEnabled',
  'floatingRailEnabled', 'customCSSEnabled', 'launchAtLoginEnabled', 'isPinned',
  'onboardingCompleted'
];

function clamp(value, minimum, maximum, fallback) {
  const number = Number(value);
  return Number.isFinite(number) ? Math.min(Math.max(number, minimum), maximum) : fallback;
}

function validAccelerator(value, fallback) {
  if (typeof value !== 'string' || value.length > 64) return fallback;
  const parts = value.split('+').map((part) => part.trim()).filter(Boolean);
  if (parts.length < 2) return fallback;
  const modifiers = new Set(['Alt', 'Shift', 'Control', 'Ctrl', 'CommandOrControl', 'Super']);
  return parts.slice(0, -1).every((part) => modifiers.has(part)) && parts.at(-1).length > 0
    ? parts.join('+')
    : fallback;
}

function validateLayoutOptions(value) {
  const source = value && typeof value === 'object' ? value : {};
  const defaults = DEFAULTS.customDiscordLayoutOptions;
  return {
    navigationPresentation: ['docked', 'floating', 'hidden'].includes(source.navigationPresentation)
      ? source.navigationPresentation : defaults.navigationPresentation,
    composerMode: ['full', 'essential', 'hidden'].includes(source.composerMode)
      ? source.composerMode : defaults.composerMode,
    hideMemberList: source.hideMemberList === true,
    hideAccountDock: source.hideAccountDock === true,
    simplifyHeader: source.simplifyHeader === true,
    compactMedia: source.compactMedia === true,
    reduceMotion: source.reduceMotion === true
  };
}

function validate(raw = {}) {
  const result = structuredClone(DEFAULTS);
  for (const [key, choices] of Object.entries(ENUMS)) {
    if (choices.includes(raw[key])) result[key] = raw[key];
  }
  for (const key of BOOLEAN_KEYS) {
    if (typeof raw[key] === 'boolean') result[key] = raw[key];
  }
  result.hoverDwellDelay = clamp(raw.hoverDwellDelay, 0, 2, DEFAULTS.hoverDwellDelay);
  result.retractionDelay = clamp(raw.retractionDelay, 0, 10, DEFAULTS.retractionDelay);
  result.sidebarWidth = clamp(raw.sidebarWidth, 320, 4096, DEFAULTS.sidebarWidth);
  result.sidebarInset = clamp(raw.sidebarInset, 0, 48, DEFAULTS.sidebarInset);
  result.themeIntensity = clamp(raw.themeIntensity, 0, 1, DEFAULTS.themeIntensity);
  result.customCSS = typeof raw.customCSS === 'string' ? raw.customCSS.slice(0, 100000) : '';
  result.customDiscordLayoutOptions = validateLayoutOptions(raw.customDiscordLayoutOptions);
  result.shortcut = validAccelerator(raw.shortcut, DEFAULTS.shortcut);
  result.navigationShortcut = validAccelerator(raw.navigationShortcut, DEFAULTS.navigationShortcut);
  result.displayWidths = {};
  if (raw.displayWidths && typeof raw.displayWidths === 'object') {
    for (const [key, value] of Object.entries(raw.displayWidths)) {
      if (key && key.length < 128) result.displayWidths[key] = clamp(value, 320, 4096, 420);
    }
  }
  return result;
}

class SettingsStore {
  constructor(filePath) {
    this.filePath = filePath;
    this.value = this.#read();
  }

  #read() {
    try {
      return validate(JSON.parse(fs.readFileSync(this.filePath, 'utf8')));
    } catch {
      return validate();
    }
  }

  save(next) {
    this.value = validate(next);
    fs.mkdirSync(path.dirname(this.filePath), { recursive: true });
    const temporary = `${this.filePath}.tmp`;
    fs.writeFileSync(temporary, `${JSON.stringify(this.value, null, 2)}\n`, { mode: 0o600 });
    fs.renameSync(temporary, this.filePath);
    return this.value;
  }

  update(patch) {
    return this.save({ ...this.value, ...patch });
  }

  reset() {
    return this.save(DEFAULTS);
  }

  widthForDisplay(displayId) {
    return this.value.displayWidths[String(displayId)] || this.value.sidebarWidth;
  }

  setWidthForDisplay(displayId, width) {
    return this.update({
      displayWidths: { ...this.value.displayWidths, [String(displayId)]: width }
    });
  }
}

module.exports = { DEFAULTS, validate, validateLayoutOptions, validAccelerator, SettingsStore };
