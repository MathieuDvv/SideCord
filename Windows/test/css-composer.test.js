'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { DEFAULTS } = require('../src/main/settings-store');
const {
  layoutOptions, customCssValidationError, configuration, compose
} = require('../src/main/css-composer');

test('quick layouts map to the Swift app presets', () => {
  assert.equal(layoutOptions({ discordLayoutMode: 'full' }).navigationPresentation, 'docked');
  assert.equal(layoutOptions({ discordLayoutMode: 'focus' }).composerMode, 'essential');
  assert.equal(layoutOptions({ discordLayoutMode: 'reader' }).composerMode, 'hidden');
});

test('custom CSS rejects every network-capable primitive', () => {
  for (const css of ['@import x', 'a{background:url(x)}', 'a{src(x)}', 'a{background:data:x}', '/* x */']) {
    assert.ok(customCssValidationError(css));
  }
  assert.equal(customCssValidationError('.tour-letter { color: #fff; }'), null);
});

test('runtime configuration emits stable theme attributes and variables', () => {
  const value = configuration({ ...structuredClone(DEFAULTS), themeAccent: 'white', discordLayoutMode: 'focus' });
  assert.equal(value.attributes['data-sidecord-theme'], 'system-glass');
  assert.equal(value.attributes['data-sidecord-navigation'], 'floating');
  assert.equal(value.variables['--sidecord-accent-color'], '#ffffff');
});

test('trusted sheets are composed with custom CSS last', () => {
  const resources = path.join(__dirname, '..', 'src', 'web');
  const css = compose({ ...structuredClone(DEFAULTS), customCSSEnabled: true, customCSS: '.mine { color: red; }' }, resources);
  assert.ok(css.includes('SideCord layout behavior'));
  assert.ok(css.includes('Windows host chrome'));
  assert.ok(css.endsWith('.mine { color: red; }'));
});
