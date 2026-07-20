'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { DEFAULTS, SettingsStore, validate, validAccelerator } = require('../src/main/settings-store');

test('defaults match the Swift app behavior with Windows accelerators', () => {
  const settings = validate();
  assert.equal(settings.sidebarEdge, 'right');
  assert.equal(settings.sidebarWidth, 420);
  assert.equal(settings.sidebarInset, 16);
  assert.equal(settings.cssPreset, 'compact');
  assert.equal(settings.shortcut, 'Alt+D');
});

test('corrupt and out-of-range values are normalized', () => {
  const settings = validate({
    sidebarEdge: 'top', sidebarWidth: -2, sidebarInset: 999,
    hoverDwellDelay: Infinity, themeIntensity: 4,
    customDiscordLayoutOptions: { navigationPresentation: 'broken', hideMemberList: true }
  });
  assert.equal(settings.sidebarEdge, 'right');
  assert.equal(settings.sidebarWidth, 320);
  assert.equal(settings.sidebarInset, 48);
  assert.equal(settings.hoverDwellDelay, .25);
  assert.equal(settings.themeIntensity, 1);
  assert.equal(settings.customDiscordLayoutOptions.navigationPresentation, 'docked');
  assert.equal(settings.customDiscordLayoutOptions.hideMemberList, true);
});

test('accelerators require a supported modifier', () => {
  assert.equal(validAccelerator('D', DEFAULTS.shortcut), DEFAULTS.shortcut);
  assert.equal(validAccelerator('Control+Shift+Space', DEFAULTS.shortcut), 'Control+Shift+Space');
});

test('settings persist atomically and widths are per display', (context) => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'sidecord-settings-'));
  context.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const file = path.join(directory, 'settings.json');
  const first = new SettingsStore(file);
  first.update({ visualTheme: 'oled' });
  first.setWidthForDisplay(42, 610);
  const second = new SettingsStore(file);
  assert.equal(second.value.visualTheme, 'oled');
  assert.equal(second.widthForDisplay(42), 610);
  assert.equal(fs.existsSync(`${file}.tmp`), false);
});
