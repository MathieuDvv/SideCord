'use strict';

const DISCORD_DOMAINS = ['discord.com', 'discordapp.com'];

function normalizedHost(value) {
  return String(value || '').toLowerCase().replace(/\.+$/, '');
}

function isDiscordHost(host) {
  const value = normalizedHost(host);
  return DISCORD_DOMAINS.some((domain) => value === domain || value.endsWith(`.${domain}`));
}

function classify(rawUrl) {
  let url;
  try {
    url = new URL(rawUrl);
  } catch {
    return 'cancel';
  }
  if (url.protocol === 'https:' && isDiscordHost(url.hostname)) return 'allow';
  if (url.protocol === 'https:') return 'external';
  return 'cancel';
}

function isAuthenticationPopup(rawUrl) {
  let url;
  try {
    url = new URL(rawUrl);
  } catch {
    return false;
  }
  if (url.protocol !== 'https:') return false;
  const host = normalizedHost(url.hostname);
  const pathname = url.pathname.toLowerCase();
  if (isDiscordHost(host)) {
    return ['/login', '/oauth2', '/api/oauth2', '/authorize'].some((prefix) => pathname.startsWith(prefix));
  }
  const exactHosts = new Set([
    'accounts.google.com', 'appleid.apple.com', 'login.microsoftonline.com',
    'login.live.com'
  ]);
  if (exactHosts.has(host)) return true;
  const scoped = {
    'github.com': '/login/oauth',
    'twitter.com': '/i/oauth',
    'x.com': '/i/oauth',
    'id.twitch.tv': '/oauth',
    'steamcommunity.com': '/openid',
    'www.facebook.com': '/dialog/oauth'
  };
  return Boolean(scoped[host] && pathname.startsWith(scoped[host]));
}

function isAllowedPermissionOrigin(rawUrl) {
  try {
    const url = new URL(rawUrl);
    return url.protocol === 'https:' && isDiscordHost(url.hostname);
  } catch {
    return false;
  }
}

module.exports = { isDiscordHost, classify, isAuthenticationPopup, isAllowedPermissionOrigin };
