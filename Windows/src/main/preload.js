'use strict';

const { ipcRenderer, webFrame } = require('electron');

const MANAGED_ATTRIBUTES = [
  'data-sidecord-navigation', 'data-sidecord-composer', 'data-sidecord-theme',
  'data-sidecord-accent', 'data-sidecord-color-scheme', 'data-sidecord-theme-intensity',
  'data-sidecord-hide-members', 'data-sidecord-hide-account-dock',
  'data-sidecord-simplify-header', 'data-sidecord-compact-media',
  'data-sidecord-reduce-motion', 'data-sidecord-floating-rail'
];

let state = ipcRenderer.sendSync('sidecord:get-state');
let drawerOpen = false;
let observer;
let reconcileQueued = false;
let lastAttentionSignature = '';
let railElements = new Map();
let lastRailPayload = '';
const settingsIntegration = {
  navButton: null,
  navButtons: [],
  sectionLabel: null,
  page: null,
  shellRoot: null,
  contentRegion: null,
  hiddenContent: [],
  selected: false,
  selectedPageKey: 'settings',
  baseClass: '',
  selectedClass: '',
  openTimer: null
};

function isDiscordPage() {
  const host = location.hostname.toLowerCase().replace(/\.+$/, '');
  return location.protocol === 'https:' && (host === 'discord.com' || host.endsWith('.discord.com')
    || host === 'discordapp.com' || host.endsWith('.discordapp.com'));
}

function isAuthenticationEntry(url) {
  const host = url.hostname.toLowerCase().replace(/\.+$/, '');
  const pathname = url.pathname.toLowerCase();
  const discord = host === 'discord.com' || host.endsWith('.discord.com')
    || host === 'discordapp.com' || host.endsWith('.discordapp.com');
  if (discord) return ['/login', '/oauth2', '/api/oauth2', '/authorize']
    .some((prefix) => pathname.startsWith(prefix));
  if (['accounts.google.com', 'appleid.apple.com', 'login.microsoftonline.com', 'login.live.com'].includes(host)) return true;
  const scoped = {
    'github.com': '/login/oauth', 'twitter.com': '/i/oauth', 'x.com': '/i/oauth',
    'id.twitch.tv': '/oauth', 'steamcommunity.com': '/openid',
    'www.facebook.com': '/dialog/oauth'
  };
  return Boolean(scoped[host] && pathname.startsWith(scoped[host]));
}

function installExternalLinkPolicy() {
  document.addEventListener('click', (event) => {
    const anchor = event.target instanceof Element ? event.target.closest('a[href]') : null;
    if (!anchor || event.defaultPrevented) return;
    let url;
    try { url = new URL(anchor.href, location.href); } catch { return; }
    if (url.protocol !== 'https:' || isAuthenticationEntry(url)) return;
    const host = url.hostname.toLowerCase().replace(/\.+$/, '');
    const discord = host === 'discord.com' || host.endsWith('.discord.com')
      || host === 'discordapp.com' || host.endsWith('.discordapp.com');
    if (discord) return;
    event.preventDefault();
    event.stopPropagation();
    ipcRenderer.send('sidecord:open-external', url.href);
  }, true);
}

function sendAction(action) {
  ipcRenderer.send('sidecord:action', action);
}

function element(tag, attributes = {}, children = []) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(attributes)) {
    if (key === 'class') node.className = value;
    else if (key === 'text') node.textContent = value;
    else if (key.startsWith('on')) node.addEventListener(key.slice(2), value);
    else if (value !== undefined) node.setAttribute(key, value);
  }
  for (const child of children) node.append(child);
  return node;
}

function button(label, title, action) {
  return element('button', {
    type: 'button', class: 'sidecord-icon-button', text: label,
    title, 'aria-label': title, onclick: action
  });
}

function mountControls() {
  if (!document.body || document.getElementById('sidecord-controls')) return;
  const controls = element('div', { id: 'sidecord-controls', 'data-sidecord-host-ui': '' }, [
    button('\uE700', 'Toggle Discord navigation', () => toggleNavigation()),
    button('\uECA5', state.settings.floatingRailEnabled ? 'Hide floating server rail' : 'Show floating server rail', () => sendAction('toggle-rail')),
    button('\uE718', state.settings.isPinned ? 'Unpin SideCord' : 'Pin SideCord', () => sendAction('pin')),
    button('\uE740', 'Maximize or restore SideCord', () => sendAction('maximize')),
    button('\uE72C', 'Reload Discord', () => sendAction('reload')),
    button('\uE713', 'Open SideCord settings', showSettings),
    button(state.settings.sidebarEdge === 'right' ? '\uE76C' : '\uE76B', 'Hide SideCord', () => sendAction('hide'))
  ]);
  for (const [index, name] of ['navigation', 'rail', 'pin', 'maximize', 'reload', 'settings', 'hide'].entries()) {
    controls.children[index].setAttribute('data-sidecord-control', name);
  }
  document.body.append(controls);
}

function toggleNavigation() {
  drawerOpen = !drawerOpen;
  document.documentElement.toggleAttribute('data-sidecord-drawer-open', drawerOpen);
}

function applyState(next) {
  state = next;
  const root = document.documentElement;
  if (!root || !next.configuration) return;
  for (const name of MANAGED_ATTRIBUTES) root.removeAttribute(name);
  for (const [name, value] of Object.entries(next.configuration.attributes)) root.setAttribute(name, value);
  for (const [name, value] of Object.entries(next.configuration.variables)) root.style.setProperty(name, value);
  const requested = next.settings.themeColorScheme;
  const scheme = requested === 'system'
    ? (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light')
    : requested;
  root.setAttribute('data-sidecord-resolved-color-scheme', scheme);
  let style = document.getElementById('sidecord-injected-css');
  if (!style) {
    style = document.createElement('style');
    style.id = 'sidecord-injected-css';
    (document.head || root).append(style);
  }
  style.textContent = next.css || '';
  mountControls();
  updateControls();
  scheduleReconcile();
  if (settingsIntegration.selected && settingsIntegration.page?.isConnected) {
    settingsIntegration.page.replaceChildren(settingsMarkup(true));
    applySettingsCategory();
  }
}

function updateControls() {
  const controls = document.getElementById('sidecord-controls');
  if (!controls) return;
  const navigation = controls.querySelector('[data-sidecord-control="navigation"]');
  const rail = controls.querySelector('[data-sidecord-control="rail"]');
  const pin = controls.querySelector('[data-sidecord-control="pin"]');
  const hide = controls.querySelector('[data-sidecord-control="hide"]');
  const docked = state.configuration?.options?.navigationPresentation === 'docked';
  navigation.hidden = docked;
  rail.hidden = docked;
  rail.title = state.settings.floatingRailEnabled ? 'Hide floating server rail' : 'Show floating server rail';
  rail.setAttribute('aria-label', rail.title);
  rail.setAttribute('aria-pressed', String(Boolean(state.settings.floatingRailEnabled)));
  rail.toggleAttribute('data-sidecord-rail-active', Boolean(state.settings.floatingRailEnabled));
  pin.textContent = '\uE718';
  pin.title = state.settings.isPinned ? 'Unpin SideCord' : 'Pin SideCord';
  pin.setAttribute('aria-label', pin.title);
  hide.textContent = state.settings.sidebarEdge === 'right' ? '\uE76C' : '\uE76B';
}

function findFirst(selectors) {
  for (const selector of selectors) {
    try {
      const value = document.querySelector(selector);
      if (value) return value;
    } catch { /* Discord changed a selector; fail open. */ }
  }
  return null;
}

function reconcileDiscordRoles() {
  reconcileQueued = false;
  const roles = {
    'guild-rail': ['nav:has([data-list-id="guildsnav"])', '[class^="guilds_"]', '[class*=" guilds_"]'],
    'channel-list': ['[class^="sidebarList_"]', '[class*=" sidebarList_"]', '[class^="sidebar_"]:has(nav)', '[class*=" sidebar_"]:has(nav)'],
    'account-dock': ['[class^="panels_"]', '[class*=" panels_"]'],
    'member-list': ['[class^="membersWrap_"]', '[class*=" membersWrap_"]']
  };
  for (const [role, selectors] of Object.entries(roles)) {
    const current = document.querySelector(`[data-sidecord-role="${role}"]`);
    if (current?.isConnected) continue;
    findFirst(selectors)?.setAttribute('data-sidecord-role', role);
  }
  reportRailItems(document.querySelector('[data-sidecord-role="guild-rail"]'));
  const scheme = document.documentElement.getAttribute('data-sidecord-resolved-color-scheme') || 'dark';
  for (const scope of [document.body, document.getElementById('app-mount')]) {
    if (scope) scope.setAttribute('data-sidecord-theme-scope', scheme);
  }
  mountControls();
  detectAttention();
  mountIntegratedSettings();
}

function safeIconSource(element) {
  const image = element?.querySelector?.('img[src]');
  const source = image?.currentSrc || image?.getAttribute('src') || '';
  if (!source || source.length > 262144) return null;
  return /^https:\/\//i.test(source) || /^data:image\/(png|jpeg|webp|gif);base64,/i.test(source)
    ? source : null;
}

function railDescriptor(candidate) {
  const listItem = candidate.closest('[data-list-item-id]') || candidate;
  const listId = listItem.getAttribute('data-list-item-id') || '';
  const anchor = candidate.closest('a[href]') || candidate.querySelector?.('a[href]');
  const href = anchor?.getAttribute('href') || '';
  let id;
  let kind;
  if (listId === 'guildsnav___home' || /\/channels\/@me(?:\/|$)/.test(href)) {
    id = 'direct-messages'; kind = 'directMessages';
  } else {
    const guildId = listId.match(/^guildsnav___(\d+)$/)?.[1]
      || href.match(/\/channels\/(\d+)(?:\/|$)/)?.[1];
    if (guildId) { id = `server:${guildId}`; kind = 'server'; }
    else if (listId === 'guildsnav___create-join-button') { id = 'action:create-server'; kind = 'action'; }
    else if (listId === 'guildsnav___guild-discover-button') { id = 'action:discover-servers'; kind = 'action'; }
  }
  if (!id || !kind) return null;
  const target = listItem.matches('a,button,[role="button"],[role="treeitem"]')
    ? listItem : anchor || candidate;
  const label = String(target.getAttribute('data-dnd-name') || target.getAttribute('aria-label')
    || target.querySelector?.('img[alt]')?.getAttribute('alt') || target.textContent || '')
    .replace(/\s+/g, ' ').trim().slice(0, 120);
  const className = String(target.className || '');
  const selected = target.getAttribute('aria-selected') === 'true'
    || target.getAttribute('aria-current') === 'page' || /(^|\s)selected[_-]/i.test(className)
    || Boolean(target.querySelector?.('[class^="selected_"],[class*=" selected_"]'));
  const unreadNode = target.querySelector?.('[class^="unread_"],[class*=" unread_"],[class^="numberBadge_"],[class*=" numberBadge_"],[aria-label*="unread" i],[aria-label*="mention" i]');
  const unread = /unread|mention/i.test(`${className} ${target.getAttribute('aria-label') || ''}`)
    || Boolean(unreadNode);
  const badge = target.querySelector?.('[class^="numberBadge_"],[class*=" numberBadge_"],[aria-label*="mention" i]');
  const mentionText = `${badge?.textContent || ''} ${badge?.getAttribute('aria-label') || ''}`;
  const mentionNumber = Number(mentionText.match(/\d+/)?.[0]);
  return {
    item: {
      id, title: label || (kind === 'directMessages' ? 'Direct Messages' : 'Discord'),
      icon: safeIconSource(target), kind, selected, unread,
      mentions: Number.isInteger(mentionNumber) && mentionNumber > 0 ? Math.min(9999, mentionNumber) : null
    },
    element: target
  };
}

function reportRailItems(guildRail) {
  if (!guildRail) return;
  const nextElements = new Map();
  const items = [];
  for (const candidate of guildRail.querySelectorAll('[data-list-item-id^="guildsnav___"],a[href*="/channels/"]')) {
    const descriptor = railDescriptor(candidate);
    if (!descriptor || nextElements.has(descriptor.item.id)) continue;
    nextElements.set(descriptor.item.id, descriptor.element);
    items.push(descriptor.item);
    if (items.length >= 200) break;
  }
  railElements = nextElements;
  const serialized = JSON.stringify(items);
  if (serialized === lastRailPayload) return;
  lastRailPayload = serialized;
  ipcRenderer.send('sidecord:rail-state', items);
}

function scheduleReconcile() {
  if (reconcileQueued) return;
  reconcileQueued = true;
  requestAnimationFrame(reconcileDiscordRoles);
}

function detectAttention() {
  const titleCount = /^\((\d+)\)/.exec(document.title)?.[1] || '';
  const incoming = findFirst([
    '[role="dialog"][aria-label*="incoming call" i]',
    '[aria-modal="true"][aria-label*="incoming call" i]',
    '[class^="ringingIncoming_"]', '[class*=" ringingIncoming_"]'
  ]);
  const signature = incoming ? 'incoming-call' : titleCount ? `unread-${titleCount}` : '';
  if (signature && signature !== lastAttentionSignature) ipcRenderer.send('sidecord:attention');
  lastAttentionSignature = signature;
}

function installNotificationBridge() {
  document.addEventListener('sidecord-notification', () => ipcRenderer.send('sidecord:attention'));
  const source = `(() => {
    if (window.__sidecordNotificationBridge) return;
    window.__sidecordNotificationBridge = true;
    const NativeNotification = window.Notification;
    if (typeof NativeNotification !== 'function') return;
    function SideCordNotification(...args) {
      document.dispatchEvent(new CustomEvent('sidecord-notification'));
      return Reflect.construct(NativeNotification, args, new.target || NativeNotification);
    }
    Object.setPrototypeOf(SideCordNotification, NativeNotification);
    SideCordNotification.prototype = NativeNotification.prototype;
    for (const key of ['permission', 'maxActions']) {
      try { Object.defineProperty(SideCordNotification, key, Object.getOwnPropertyDescriptor(NativeNotification, key)); } catch {}
    }
    SideCordNotification.requestPermission = (...args) => NativeNotification.requestPermission(...args);
    window.Notification = SideCordNotification;
  })();`;
  webFrame.executeJavaScript(source, true).catch(() => {});
}

function field(label, control, detail = '') {
  return element('label', { class: 'sidecord-field' }, [
    element('span', { class: 'sidecord-field-copy' }, [
      element('b', { text: label }),
      ...(detail ? [element('small', { text: detail })] : [])
    ]),
    control
  ]);
}

function select(name, choices, selected) {
  const control = element('select', { name, 'data-setting': name });
  for (const [value, label] of choices) {
    const option = element('option', { value, text: label });
    option.selected = value === selected;
    control.append(option);
  }
  return control;
}

function checkbox(name, checked) {
  const input = element('input', { type: 'checkbox', name, 'data-setting': name });
  input.checked = checked;
  return input;
}

function numberInput(name, value, min, max, step) {
  return element('input', { type: 'number', name, value, min, max, step, 'data-setting': name });
}

const SETTINGS_PAGE_TITLES = Object.freeze({
  theme: 'SideCord Theme',
  layout: 'SideCord Layout',
  settings: 'SideCord Settings'
});

function applySettingsCategory() {
  const bridge = settingsIntegration;
  const pageKey = SETTINGS_PAGE_TITLES[bridge.selectedPageKey] ? bridge.selectedPageKey : 'settings';
  bridge.selectedPageKey = pageKey;
  bridge.page?.setAttribute('data-sidecord-selected-page', pageKey);
  const title = bridge.page?.querySelector('[data-sidecord-page-title]');
  if (title) title.textContent = SETTINGS_PAGE_TITLES[pageKey];
  if (bridge.page && bridge.shellRoot) adoptDiscordInputStyles(bridge.page, bridge.shellRoot);
}

function settingsMarkup(integrated = false) {
  const s = state.settings;
  const options = state.configuration.options;
  const form = element('form', {
    class: `sidecord-settings-card${integrated ? ' sidecord-integrated-card' : ''}`
  });
  form.append(
    element('div', { class: 'sidecord-settings-header' }, [
      element('div', {}, [
        element('h1', { text: SETTINGS_PAGE_TITLES[settingsIntegration.selectedPageKey] || 'SideCord Settings', 'data-sidecord-page-title': '' }),
        element('p', { text: 'Discord, one edge away.' })
      ]),
      ...(integrated ? [] : [button('\uE711', 'Close settings', hideOverlays)])
    ]),
    element('section', { 'data-sidecord-page': 'settings' }, [
      element('h2', { text: 'Sidebar' }),
      field('Screen edge', select('sidebarEdge', [['left', 'Left'], ['right', 'Right']], s.sidebarEdge), 'Where SideCord waits.'),
      field('Edge reveal', checkbox('edgeHoverEnabled', s.edgeHoverEnabled), 'Reveal when the pointer rests at the edge.'),
      field('Default width', numberInput('sidebarWidth', s.sidebarWidth, 320, 1600, 10), 'Width used for new displays.'),
      field('Floating inset', numberInput('sidebarInset', s.sidebarInset, 0, 48, 1), 'Space around the SideCord panel.'),
      field('Hover delay', numberInput('hoverDwellDelay', s.hoverDwellDelay, 0, 2, .05), 'Seconds before edge reveal.'),
      field('Retraction delay', numberInput('retractionDelay', s.retractionDelay, 0, 10, .1), 'Seconds before SideCord hides.'),
      field('Launch with Windows', checkbox('launchAtLoginEnabled', s.launchAtLoginEnabled), 'Open SideCord after signing in to Windows.')
    ]),
    element('section', { 'data-sidecord-page': 'layout' }, [
      element('h2', { text: 'Discord layout' }),
      field('Layout preset', select('discordLayoutMode', [['full', 'Full'], ['focus', 'Focus'], ['reader', 'Reader'], ['custom', 'Custom']], s.discordLayoutMode), 'Choose the amount of Discord chrome.'),
      field('Density', select('cssPreset', [['default', 'Default'], ['compact', 'Compact']], s.cssPreset), 'Adjust spacing throughout Discord.'),
      field('Navigation', select('layout.navigationPresentation', [['docked', 'Docked'], ['floating', 'Floating'], ['hidden', 'Hidden']], options.navigationPresentation), 'Keep channels docked, in a drawer, or hidden.'),
      field('Message composer', select('layout.composerMode', [['full', 'Full'], ['essential', 'Essential'], ['hidden', 'Hidden']], options.composerMode), 'Choose how much of the composer remains visible.'),
      field('Floating server rail', checkbox('floatingRailEnabled', s.floatingRailEnabled), 'Keep servers in a detached SideCord rail.'),
      field('Hide member list', checkbox('layout.hideMemberList', options.hideMemberList), 'Give conversations more horizontal room.'),
      field('Hide account and voice dock', checkbox('layout.hideAccountDock', options.hideAccountDock), 'Remove the lower account controls.'),
      field('Simplify header', checkbox('layout.simplifyHeader', options.simplifyHeader), 'Keep only essential channel actions.'),
      field('Limit tall message media', checkbox('layout.compactMedia', options.compactMedia), 'Constrain oversized images and video.'),
      field('Reduce Discord motion', checkbox('layout.reduceMotion', options.reduceMotion), 'Minimize animated Discord transitions.')
    ]),
    element('section', { 'data-sidecord-page': 'theme' }, [
      element('h2', { text: 'Appearance' }),
      field('Theme', select('visualTheme', [['systemGlass', 'Mica'], ['discord', 'Discord'], ['oled', 'OLED'], ['soft', 'Soft']], s.visualTheme), 'Mica uses the native Windows backdrop material.'),
      field('Accent', select('themeAccent', [['automatic', 'Automatic'], ['blurple', 'Blurple'], ['blue', 'Blue'], ['purple', 'Purple'], ['pink', 'Pink'], ['green', 'Green'], ['orange', 'Orange'], ['white', 'White']], s.themeAccent), 'Used by controls and the optional glow.'),
      field('Color scheme', select('themeColorScheme', [['system', 'System'], ['light', 'Light'], ['dark', 'Dark']], s.themeColorScheme), 'Follow Windows or force an appearance.'),
      field('Theme intensity', numberInput('themeIntensity', s.themeIntensity, 0, 1, .05), 'Strength of SideCord surfaces.'),
      field('Glow for Discord activity', checkbox('notificationGlowEnabled', s.notificationGlowEnabled), 'Pulse the configured screen edge.'),
      field('Glow color', select('attentionGlowColor', [['followTheme', 'Follow theme'], ['blurple', 'Blurple'], ['blue', 'Blue'], ['purple', 'Purple'], ['pink', 'Pink'], ['green', 'Green'], ['orange', 'Orange'], ['white', 'White']], s.attentionGlowColor), 'Use the theme accent or a dedicated color.'),
      field('Glow strength', select('attentionGlowStrength', [['subtle', 'Subtle'], ['normal', 'Normal'], ['strong', 'Strong']], s.attentionGlowStrength), 'Visual intensity of the edge bloom.')
    ]),
    element('section', { 'data-sidecord-page': 'settings' }, [
      element('h2', { text: 'Shortcuts' }),
      field('Show or hide', element('input', { name: 'shortcut', value: s.shortcut, 'data-setting': 'shortcut' }), 'Reveal or retract SideCord.'),
      field('Toggle navigation', element('input', { name: 'navigationShortcut', value: s.navigationShortcut, 'data-setting': 'navigationShortcut' }), 'Open or close floating channels.'),
      element('p', { class: 'sidecord-help', text: 'Use Electron accelerator names, such as Alt+D or Control+Shift+Space.' })
    ]),
    element('section', { 'data-sidecord-page': 'theme' }, [
      element('h2', { text: 'Custom CSS' }),
      field('Enable local custom CSS', checkbox('customCSSEnabled', s.customCSSEnabled), 'Apply local CSS after the selected theme.'),
      element('textarea', { name: 'customCSS', 'data-setting': 'customCSS', rows: '7', spellcheck: 'false' })
    ]),
    element('div', { class: 'sidecord-settings-footer' }, [
      element('span', { id: 'sidecord-settings-status', 'aria-live': 'polite' }),
      element('button', { type: 'button', class: 'sidecord-secondary', text: 'Reset defaults', onclick: resetSettings }),
      element('button', {
        type: 'button', class: 'sidecord-primary', text: 'Done',
        onclick: integrated ? deselectIntegratedSettings : hideOverlays
      })
    ])
  );
  form.querySelector('[name="customCSS"]').value = s.customCSS;
  form.addEventListener('change', saveSetting);
  return form;
}

function ensureOverlay(id) {
  let overlay = document.getElementById(id);
  if (!overlay) {
    overlay = element('div', { id, class: 'sidecord-overlay', 'data-sidecord-host-ui': '' });
    overlay.addEventListener('mousedown', (event) => {
      if (event.target === overlay) hideOverlays();
    });
    document.body.append(overlay);
  }
  return overlay;
}

function showSettings() {
  settingsIntegration.selected = true;
  if (mountIntegratedSettings()) {
    selectIntegratedSettings();
    return;
  }
  const findSettingsButton = () => findFirst([
    'button[aria-label*="User Settings" i]', 'button[aria-label="Settings" i]',
    '[role="button"][aria-label*="User Settings" i]', '[data-list-item-id*="settings" i]',
    'button[aria-label*="param" i]', 'button[aria-label*="einstellungen" i]',
    'button[aria-label*="ajustes" i]', 'button[aria-label*="impostazioni" i]'
  ]);
  const activate = (target) => {
    let current = target;
    for (let depth = 0; current && depth < 3; depth += 1) {
      const key = Object.keys(current).find((candidate) => candidate.startsWith('__reactProps$'));
      const onClick = key ? current[key]?.onClick : null;
      if (typeof onClick === 'function') {
        try {
          onClick({
            type: 'click', button: 0, target, currentTarget: current,
            preventDefault() {}, stopPropagation() {}, persist() {},
            isDefaultPrevented: () => false, isPropagationStopped: () => false
          });
          return;
        } catch { /* Fall back to the DOM click below. */ }
      }
      current = current.parentElement;
    }
    target?.click?.();
  };
  let attempts = 0;
  const poll = () => {
    attempts += 1;
    if (mountIntegratedSettings()) {
      clearInterval(settingsIntegration.openTimer);
      settingsIntegration.openTimer = null;
      selectIntegratedSettings();
      settingsIntegration.navButton?.scrollIntoView?.({ block: 'center', behavior: 'smooth' });
      return;
    }
    if (attempts === 1 || attempts % 16 === 0) activate(findSettingsButton());
    if (attempts >= 160) {
      clearInterval(settingsIntegration.openTimer);
      settingsIntegration.openTimer = null;
    }
  };
  poll();
  if (!settingsIntegration.openTimer) settingsIntegration.openTimer = setInterval(poll, 125);
}

function classNames(node) {
  return typeof node?.className === 'string' ? node.className.split(/\s+/).filter(Boolean) : [];
}

function hasClassStem(node, stem) {
  const lower = stem.toLowerCase();
  return classNames(node).some((name) => name.toLowerCase() === lower
    || name.toLowerCase().startsWith(`${lower}_`));
}

function queryStem(root, stem) {
  try { return root?.querySelector(`[class="${stem}"],[class^="${stem}_"],[class*=" ${stem}_"]`) || null; }
  catch { return null; }
}

function queryAllStem(root, stem) {
  try { return [...(root?.querySelectorAll(`[class="${stem}"],[class^="${stem}_"],[class*=" ${stem}_"]`) || [])]; }
  catch { return []; }
}

function resolveSettingsShell() {
  const mobileSidebar = [...document.querySelectorAll('aside')].reverse().find((aside) => {
    try { return Boolean(aside.querySelector('nav [class*="sublist" i]')); }
    catch { return false; }
  });
  if (mobileSidebar) {
    const root = mobileSidebar.parentElement;
    const content = root && [...root.children].find((child) => hasClassStem(child, 'content'));
    if (root && content) return {
      root, sidebar: mobileSidebar, content, contentRegion: content, mobile: true
    };
  }
  let root = [...document.querySelectorAll('[class*="standardSidebarView" i]')].at(-1);
  if (!root) {
    const sidebarRegion = [...document.querySelectorAll('[class*="sidebarRegion" i]')].at(-1);
    let candidate = sidebarRegion?.parentElement;
    while (candidate && candidate !== document.body) {
      if (candidate.querySelector('[class*="contentRegion" i]')) { root = candidate; break; }
      candidate = candidate.parentElement;
    }
  }
  if (!root) return null;
  const sidebarRegion = queryStem(root, 'sidebarRegion') || root.querySelector('[class*="sidebarRegion" i]');
  const contentRegion = queryStem(root, 'contentRegion') || root.querySelector('[class*="contentRegion" i]');
  const sidebar = sidebarRegion && (queryStem(sidebarRegion, 'sidebar') || sidebarRegion.querySelector('nav') || sidebarRegion);
  const content = contentRegion && (queryStem(contentRegion, 'contentColumn') || contentRegion.querySelector('main') || contentRegion);
  return sidebar && content ? { root, sidebar, content, contentRegion, mobile: false } : null;
}

function navigationItems(host) {
  return [...(host?.children || [])].filter((child) => child.matches?.('button,[role="tab"],[role="button"],[tabindex]')
    || hasClassStem(child, 'item'));
}

function resolveNavigationHost(sidebar) {
  const mobileList = queryStem(sidebar, 'sublist');
  if (mobileList) return mobileList;
  const candidates = [sidebar, ...sidebar.querySelectorAll('nav,[role="tablist"],div')];
  const score = (candidate) => navigationItems(candidate).length * 20
    + (hasClassStem(candidate, 'side') ? 30 : 0)
    + (candidate.tagName?.toLowerCase() === 'nav' ? 12 : 0);
  return candidates.reduce((best, candidate) => score(candidate) > score(best) ? candidate : best, sidebar);
}

function mountMobileSettingsNavigation(navigationHost) {
  const bridge = settingsIntegration;
  const sections = [...navigationHost.children].filter((child) => hasClassStem(child, 'section'));
  const sectionTemplate = sections.find((section) => queryStem(section, 'sectionLabel')
    && queryStem(section, 'sectionList'));
  const listTemplate = sectionTemplate && queryStem(sectionTemplate, 'sectionList');
  const itemContainerTemplate = listTemplate && queryStem(listTemplate, 'itemContainer');
  const itemTemplate = itemContainerTemplate && queryStem(itemContainerTemplate, 'item');
  if (!sectionTemplate || !listTemplate || !itemContainerTemplate || !itemTemplate) return false;
  const section = document.createElement('li');
  section.className = sectionTemplate.className;
  section.setAttribute('data-sidecord-settings-heading', '');
  const label = queryStem(sectionTemplate, 'sectionLabel').cloneNode(true);
  (label.querySelector('h1,h2,h3,h4,span') || label).textContent = 'SideCord';
  section.append(label);
  const list = document.createElement('ul');
  list.className = listTemplate.className;
  bridge.baseClass = classNames(itemTemplate).filter((name) => !/^active_|^destructive_/.test(name)).join(' ');
  const activeTemplate = queryAllStem(navigationHost, 'item').find((item) => classNames(item).some((name) => /^active_/.test(name)));
  bridge.selectedClass = activeTemplate?.className || bridge.baseClass;
  bridge.navButtons = [];
  for (const [pageKey, title] of [['theme', 'Theme'], ['layout', 'Layout'], ['settings', 'Settings']]) {
    const container = document.createElement('li');
    container.className = itemContainerTemplate.className;
    const buttonNode = document.createElement('div');
    buttonNode.className = bridge.baseClass;
    wireSettingsNavigationButton(buttonNode, pageKey, title, 'link');
    container.append(buttonNode);
    list.append(container);
    bridge.navButtons.push(buttonNode);
  }
  section.append(list);
  navigationHost.insertBefore(section, sections.at(-1) || null);
  bridge.sectionLabel = section;
  bridge.navButton = bridge.navButtons.find((buttonNode) => buttonNode.dataset.sidecordSettingsNav === bridge.selectedPageKey)
    || bridge.navButtons.at(-1);
  return true;
}

function wireSettingsNavigationButton(buttonNode, pageKey, title, role = 'tab') {
  buttonNode.textContent = title;
  buttonNode.setAttribute('role', role);
  buttonNode.setAttribute('tabindex', '0');
  buttonNode.setAttribute('data-sidecord-settings-nav', pageKey);
  buttonNode.addEventListener('click', (event) => {
    event.stopPropagation();
    selectIntegratedSettings(pageKey);
  });
  buttonNode.addEventListener('keydown', (event) => {
    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      selectIntegratedSettings(pageKey);
    }
  });
}

function restoreDiscordSettingsContent() {
  for (const record of settingsIntegration.hiddenContent) {
    if (!record.node?.isConnected) continue;
    if (record.display) record.node.style.setProperty('display', record.display, record.priority);
    else record.node.style.removeProperty('display');
    if (record.ariaHidden === null) record.node.removeAttribute('aria-hidden');
    else record.node.setAttribute('aria-hidden', record.ariaHidden);
  }
  settingsIntegration.hiddenContent = [];
}

function selectIntegratedSettings(pageKey = settingsIntegration.selectedPageKey) {
  const bridge = settingsIntegration;
  if (!SETTINGS_PAGE_TITLES[pageKey]) pageKey = 'settings';
  bridge.selectedPageKey = pageKey;
  bridge.navButton = bridge.navButtons.find((buttonNode) => buttonNode.dataset.sidecordSettingsNav === pageKey)
    || bridge.navButton;
  if (!bridge.page?.isConnected || !bridge.navButton?.isConnected || !bridge.contentRegion) return false;
  bridge.selected = true;
  bridge.page.hidden = false;
  for (const buttonNode of bridge.navButtons) {
    const selected = buttonNode === bridge.navButton;
    buttonNode.setAttribute('aria-selected', String(selected));
    buttonNode.className = selected ? (bridge.selectedClass || bridge.baseClass) : bridge.baseClass;
    buttonNode.style.background = selected && !bridge.selectedClass ? 'var(--background-modifier-selected)' : '';
  }
  if (!bridge.hiddenContent.length) {
    for (const node of [...bridge.contentRegion.children]) {
      if (node === bridge.page) continue;
      bridge.hiddenContent.push({
        node,
        display: node.style.getPropertyValue('display'),
        priority: node.style.getPropertyPriority('display'),
        ariaHidden: node.getAttribute('aria-hidden')
      });
      node.style.setProperty('display', 'none', 'important');
      node.setAttribute('aria-hidden', 'true');
    }
  }
  if (!bridge.page.firstElementChild) bridge.page.append(settingsMarkup(true));
  applySettingsCategory();
  return true;
}

function deselectIntegratedSettings() {
  const bridge = settingsIntegration;
  bridge.selected = false;
  if (bridge.page) bridge.page.hidden = true;
  for (const buttonNode of bridge.navButtons) {
    buttonNode.setAttribute('aria-selected', 'false');
    buttonNode.className = bridge.baseClass;
    buttonNode.style.background = '';
  }
  restoreDiscordSettingsContent();
}

function mountIntegratedSettings() {
  const bridge = settingsIntegration;
  const shell = resolveSettingsShell();
  if (!shell) return false;
  bridge.shellRoot = shell.root;
  const navigationHost = resolveNavigationHost(shell.sidebar);
  if (!bridge.navButtons.length || bridge.navButtons.some((buttonNode) => !buttonNode.isConnected)) {
    bridge.navButton = null;
    bridge.navButtons = [];
    bridge.sectionLabel = null;
    if (shell.mobile && mountMobileSettingsNavigation(navigationHost)) {
      // The compact Discord settings shell groups entries into semantic lists.
    } else {
    const items = navigationItems(navigationHost);
    const selectedTemplate = items.find((item) => item.getAttribute('aria-selected') === 'true'
      || hasClassStem(item, 'selected'));
    const template = items.find((item) => item !== selectedTemplate
      && !/danger|logout|red/i.test(String(item.className || ''))) || selectedTemplate;
    if (!template) return false;
    bridge.baseClass = typeof template.className === 'string' ? template.className : '';
    bridge.selectedClass = typeof selectedTemplate?.className === 'string' ? selectedTemplate.className : bridge.baseClass;
    const danger = [...navigationHost.children].find((child) => /danger|logout|red/i.test(String(child.className || ''))
      || /logout|log-out/i.test(String(child.getAttribute?.('data-list-item-id') || '')));
    const headingTemplate = [...navigationHost.children].find((child) => !items.includes(child)
      && /header|section|title/i.test(String(child.className || '')) && String(child.textContent || '').trim());
    if (headingTemplate) {
      const heading = document.createElement(headingTemplate.tagName.toLowerCase());
      heading.className = headingTemplate.className;
      heading.textContent = 'SideCord';
      heading.setAttribute('data-sidecord-settings-heading', '');
      navigationHost.insertBefore(heading, danger || null);
      bridge.sectionLabel = heading;
    }
    for (const [pageKey, title] of [['theme', 'Theme'], ['layout', 'Layout'], ['settings', 'Settings']]) {
      const tag = template.tagName.toLowerCase();
      const buttonNode = document.createElement(tag);
      if (tag === 'button') buttonNode.type = 'button';
      buttonNode.className = bridge.baseClass;
      if (!buttonNode.className) buttonNode.style.cssText = 'width:100%;border:0;border-radius:4px;padding:8px 10px;text-align:left;color:var(--interactive-normal);background:transparent;font:inherit;font-weight:500;cursor:pointer';
      wireSettingsNavigationButton(buttonNode, pageKey, title);
      navigationHost.insertBefore(buttonNode, danger || null);
      bridge.navButtons.push(buttonNode);
    }
    bridge.navButton = bridge.navButtons.find((buttonNode) => buttonNode.dataset.sidecordSettingsNav === bridge.selectedPageKey)
      || bridge.navButtons.at(-1);
    }
  }
  if (!bridge.page?.isConnected) {
    restoreDiscordSettingsContent();
    const page = element('div', {
      'data-sidecord-settings-page': '', 'data-sidecord-host-ui': ''
    });
    page.hidden = true;
    const region = shell.contentRegion || shell.content;
    if (getComputedStyle(region).position === 'static') region.style.position = 'relative';
    region.append(page);
    bridge.page = page;
    bridge.contentRegion = region;
  }
  for (const item of navigationHost.querySelectorAll('button,[role="tab"],[role="button"],[role="link"]')) {
    if (bridge.navButtons.includes(item) || item.dataset.sidecordSettingsBound) continue;
    item.dataset.sidecordSettingsBound = 'true';
    item.addEventListener('click', deselectIntegratedSettings);
  }
  if (bridge.selected) selectIntegratedSettings();
  return true;
}

function adoptDiscordInputStyles(page, shellRoot) {
  const findNative = (selector) => [...shellRoot.querySelectorAll(selector)]
    .find((candidate) => !candidate.closest('[data-sidecord-settings-page]') && typeof candidate.className === 'string');
  const prototypes = [
    ['select[data-setting]', findNative('select')],
    ['input[data-setting]:not([type="checkbox"]):not([type="range"])', findNative('input:not([type="checkbox"]):not([type="range"])')],
    ['textarea[data-setting]', findNative('textarea')]
  ];
  for (const [selector, prototype] of prototypes) {
    if (!prototype?.className) continue;
    for (const control of page.querySelectorAll(selector)) {
      control.className = `${control.className} ${prototype.className}`.trim();
      control.setAttribute('data-sidecord-native-input-style', '');
    }
  }
}

function hideOverlays() {
  document.querySelectorAll('.sidecord-overlay').forEach((node) => { node.hidden = true; });
}

async function saveSetting(event) {
  const target = event.target;
  const key = target.dataset.setting;
  if (!key) return;
  let value = target.type === 'checkbox' ? target.checked : target.value;
  if (target.type === 'number') value = Number(value);
  let patch;
  if (key.startsWith('layout.')) {
    const layoutKey = key.slice(7);
    patch = {
      discordLayoutMode: 'custom',
      customDiscordLayoutOptions: { ...state.configuration.options, [layoutKey]: value }
    };
  } else {
    patch = { [key]: value };
  }
  const result = await ipcRenderer.invoke('sidecord:update-settings', patch);
  const status = document.getElementById('sidecord-settings-status');
  if (status) status.textContent = result.ok ? 'Saved' : result.error || 'Could not save this setting.';
}

async function resetSettings() {
  const result = await ipcRenderer.invoke('sidecord:reset-settings');
  if (result.ok) applyState({ ...state, ...result, configuration: state.configuration, css: state.css });
}

function start() {
  if (!isDiscordPage()) return;
  applyState({ ...state, configuration: { attributes: {}, variables: {}, options: {} }, css: '' });
  observer = new MutationObserver(scheduleReconcile);
  observer.observe(document.documentElement, { childList: true, subtree: true, attributes: false });
  installNotificationBridge();
  installExternalLinkPolicy();
  scheduleReconcile();
  ipcRenderer.send('sidecord:renderer-ready');
}

ipcRenderer.on('sidecord:state', (_event, next) => applyState(next));
ipcRenderer.on('sidecord:toggle-navigation', toggleNavigation);
ipcRenderer.on('sidecord:activate-rail', (_event, id) => {
  if (typeof id !== 'string' || id.length > 128) return;
  const target = railElements.get(id);
  if (target?.isConnected && typeof target.click === 'function') target.click();
});
ipcRenderer.on('sidecord:show-settings', showSettings);
ipcRenderer.on('sidecord:load-error', (_event, error) => {
  const overlay = ensureOverlay('sidecord-error-overlay');
  overlay.replaceChildren(element('div', { class: 'sidecord-onboarding-card' }, [
    element('h1', { text: 'Discord could not load' }),
    element('p', { text: error.description || 'Check your connection and try again.' }),
    element('button', { type: 'button', class: 'sidecord-primary', text: 'Try again', onclick: () => sendAction('reload') })
  ]));
  overlay.hidden = false;
});

if (document.readyState === 'loading') window.addEventListener('DOMContentLoaded', start, { once: true });
else start();

window.addEventListener('beforeunload', () => observer?.disconnect());
