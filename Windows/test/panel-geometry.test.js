'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const geometry = require('../src/main/panel-geometry');

test('right and left sidebars anchor inside a negative-origin work area', () => {
  const area = { x: -1920, y: 40, width: 1920, height: 1040 };
  assert.deepEqual(geometry.sidebarBounds(area, 'right', 420, 16), {
    x: -436, y: 56, width: 420, height: 1008
  });
  assert.deepEqual(geometry.sidebarBounds(area, 'left', 420, 16), {
    x: -1904, y: 56, width: 420, height: 1008
  });
});

test('width is constrained to eighty percent and remaining inset space', () => {
  const area = { x: 0, y: 0, width: 400, height: 300 };
  assert.equal(geometry.constrainedWidth(1000, area), 320);
  assert.equal(geometry.constrainedWidth(1000, area, 48), 304);
});

test('hidden bounds move fully past the physical screen edge', () => {
  const visible = { x: 1500, y: 0, width: 420, height: 1040 };
  const display = { x: 0, y: 0, width: 1920, height: 1080 };
  assert.equal(geometry.hiddenBounds(visible, display, 'right').x, 1924);
  assert.equal(geometry.hiddenBounds(visible, display, 'left').x, -424);
});

test('an adjacent display blocks only the shared edge', () => {
  const left = { id: 1, bounds: { x: 0, y: 0, width: 1920, height: 1080 } };
  const right = { id: 2, bounds: { x: 1920, y: 0, width: 1920, height: 1080 } };
  assert.equal(geometry.isEdgeExposed(left, 'right', 500, [left, right]), false);
  assert.equal(geometry.isEdgeExposed(left, 'left', 500, [left, right]), true);
});

test('floating rail stays outside the sidebar toward screen center', () => {
  const area = { x: 0, y: 0, width: 1920, height: 1080 };
  assert.deepEqual(geometry.railBounds({ x: 1484, y: 16, width: 420, height: 1048 }, area, 'right'), {
    x: 1396, y: 28, width: 76, height: 1024
  });
  assert.deepEqual(geometry.railBounds({ x: 16, y: 16, width: 420, height: 1048 }, area, 'left'), {
    x: 448, y: 28, width: 76, height: 1024
  });
});

test('onboarding companion floats beside the sidebar and stays onscreen', () => {
  const area = { x: 0, y: 0, width: 1920, height: 1080 };
  const bounds = geometry.onboardingCompanionBounds(
    { x: 1484, y: 16, width: 420, height: 1048 }, area, 'right'
  );
  assert.deepEqual(bounds, { x: 1036, y: 215, width: 430, height: 650 });
});
