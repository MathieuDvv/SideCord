'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { materialFor } = require('../src/main/window-material');

test('Mica uses the Windows system material with a transparent content background', () => {
  assert.deepEqual(materialFor({ visualTheme: 'systemGlass', themeColorScheme: 'dark' }, null, 'win32', '10.0.22621'), {
    material: 'mica', color: '#00000000'
  });
});

test('Mica falls back to an opaque palette before Windows 11 22H2', () => {
  assert.deepEqual(materialFor({ visualTheme: 'systemGlass', themeColorScheme: 'dark' }, null, 'win32', '10.0.22000'), {
    material: 'none', color: '#14171E'
  });
});

test('OLED disables material and stays fully opaque', () => {
  assert.deepEqual(materialFor({ visualTheme: 'oled', themeColorScheme: 'dark' }, null, 'win32'), {
    material: 'none', color: '#000000'
  });
  assert.equal(materialFor({ visualTheme: 'oled', themeColorScheme: 'light' }, null, 'win32').color, '#000000');
});

test('system color scheme follows Windows for opaque themes', () => {
  assert.equal(materialFor({ visualTheme: 'discord', themeColorScheme: 'system' }, {
    shouldUseDarkColors: false
  }, 'win32').color, '#FFFFFF');
});
