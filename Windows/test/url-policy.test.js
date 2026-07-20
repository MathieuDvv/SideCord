'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  classify, isDiscordHost, isAuthenticationPopup, isAllowedPermissionOrigin
} = require('../src/main/url-policy');

test('allows only HTTPS Discord hosts using label boundaries', () => {
  assert.equal(classify('https://discord.com/app'), 'allow');
  assert.equal(classify('https://ptb.discord.com/channels/@me'), 'allow');
  assert.equal(classify('https://cdn.discordapp.com/file'), 'allow');
  assert.equal(isDiscordHost('discord.com.evil.test'), false);
  assert.equal(isDiscordHost('notdiscord.com'), false);
});

test('externalizes unrelated HTTPS and cancels unsafe schemes', () => {
  assert.equal(classify('https://example.com'), 'external');
  assert.equal(classify('http://discord.com'), 'cancel');
  assert.equal(classify('javascript:alert(1)'), 'cancel');
  assert.equal(classify('not a url'), 'cancel');
});

test('media permission origins use the same strict Discord policy', () => {
  assert.equal(isAllowedPermissionOrigin('https://discord.com'), true);
  assert.equal(isAllowedPermissionOrigin('https://discord.com.evil.test'), false);
  assert.equal(isAllowedPermissionOrigin('http://discord.com'), false);
});

test('authentication popups are narrowly scoped to known provider entry points', () => {
  assert.equal(isAuthenticationPopup('https://discord.com/oauth2/authorize?x=1'), true);
  assert.equal(isAuthenticationPopup('https://accounts.google.com/o/oauth2/auth'), true);
  assert.equal(isAuthenticationPopup('https://github.com/login/oauth/authorize'), true);
  assert.equal(isAuthenticationPopup('https://github.com/settings/profile'), false);
  assert.equal(isAuthenticationPopup('https://accounts.google.com.evil.test/o/oauth2'), false);
  assert.equal(isAuthenticationPopup('http://accounts.google.com/o/oauth2'), false);
});
