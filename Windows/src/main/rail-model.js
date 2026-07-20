'use strict';

const MAXIMUM_ITEMS = 200;
const ID_PATTERN = /^[A-Za-z0-9:@._-]+$/;
const KINDS = new Set(['directMessages', 'server', 'action']);

function safeIcon(value) {
  if (value === null || value === undefined || value === '') return null;
  if (typeof value !== 'string' || Buffer.byteLength(value) > 256 * 1024) return undefined;
  if (/^data:image\/(png|jpeg|webp|gif);base64,/i.test(value)) return value;
  try {
    const url = new URL(value);
    const host = url.hostname.toLowerCase().replace(/\.+$/, '');
    const allowed = ['discord.com', 'discordapp.com', 'discordapp.net'].some(
      (domain) => host === domain || host.endsWith(`.${domain}`)
    );
    return url.protocol === 'https:' && !url.username && !url.password && allowed ? value : undefined;
  } catch {
    return undefined;
  }
}

function validateRailItems(value) {
  if (!Array.isArray(value) || value.length > MAXIMUM_ITEMS) return null;
  const identifiers = new Set();
  const result = [];
  for (const raw of value) {
    if (!raw || typeof raw !== 'object') return null;
    const id = typeof raw.id === 'string' ? raw.id : '';
    const title = typeof raw.title === 'string' ? raw.title.trim().slice(0, 120) : '';
    const icon = safeIcon(raw.icon);
    const mentions = raw.mentions === null || raw.mentions === undefined
      ? null : Number(raw.mentions);
    if (!id || id.length > 128 || !ID_PATTERN.test(id) || identifiers.has(id)
      || !title || !KINDS.has(raw.kind) || typeof raw.selected !== 'boolean'
      || typeof raw.unread !== 'boolean' || icon === undefined
      || (mentions !== null && (!Number.isInteger(mentions) || mentions < 1 || mentions > 9999))) {
      return null;
    }
    identifiers.add(id);
    result.push({ id, title, icon, kind: raw.kind, selected: raw.selected, unread: raw.unread, mentions });
  }
  return result;
}

module.exports = { MAXIMUM_ITEMS, validateRailItems };
