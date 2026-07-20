'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { validateRailItems } = require('../src/main/rail-model');

const valid = {
  id: 'server:123', title: 'SideCord', icon: 'https://cdn.discordapp.com/icons/123/a.png',
  kind: 'server', selected: true, unread: false, mentions: null
};

test('accepts bounded Discord rail metadata', () => {
  assert.deepEqual(validateRailItems([valid]), [valid]);
});

test('rejects duplicate IDs, unsafe assets, and malformed booleans', () => {
  assert.equal(validateRailItems([valid, valid]), null);
  assert.equal(validateRailItems([{ ...valid, icon: 'https://evil.test/icon.png' }]), null);
  assert.equal(validateRailItems([{ ...valid, selected: 1 }]), null);
});
