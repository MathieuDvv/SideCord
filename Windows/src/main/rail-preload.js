'use strict';

const { ipcRenderer } = require('electron');

window.addEventListener('DOMContentLoaded', () => {
  const root = document.getElementById('rail');
  let settings = {};
  let items = [];

  const render = () => {
    document.documentElement.dataset.scheme = settings.themeColorScheme || 'system';
    document.documentElement.dataset.theme = settings.visualTheme || 'systemGlass';
    document.documentElement.style.setProperty('--accent', {
      automatic: '#5865f2', blurple: '#5865f2', blue: '#0a84ff', purple: '#af52de',
      pink: '#ff2d55', green: '#30d158', orange: '#ff9f0a', white: '#ffffff'
    }[settings.themeAccent] || '#5865f2');
    root.replaceChildren();
    if (!items.length) {
      const loading = document.createElement('div');
      loading.className = 'loading';
      loading.setAttribute('aria-label', 'Loading Discord servers');
      root.append(loading);
      return;
    }
    const direct = items.filter((item) => item.kind === 'directMessages');
    const remaining = items.filter((item) => item.kind !== 'directMessages');
    for (const [index, item] of [...direct, ...remaining].entries()) {
      if (index === direct.length && direct.length && remaining.length) {
        const separator = document.createElement('div');
        separator.className = 'separator';
        root.append(separator);
      }
      const button = document.createElement('button');
      button.type = 'button';
      button.className = `rail-item ${item.selected ? 'selected' : ''}`;
      button.title = item.title;
      button.setAttribute('aria-label', item.title);
      if (item.mentions) button.setAttribute('aria-description', `${item.mentions} unread mentions`);
      else if (item.unread) button.setAttribute('aria-description', 'Unread');
      button.addEventListener('click', () => ipcRenderer.send('sidecord:rail-activate', item.id));
      const indicator = document.createElement('span');
      indicator.className = `indicator ${item.unread ? 'unread' : ''}`;
      button.append(indicator);
      if (item.icon) {
        const image = document.createElement('img');
        image.src = item.icon;
        image.alt = '';
        image.referrerPolicy = 'no-referrer';
        image.addEventListener('error', () => {
          image.replaceWith(Object.assign(document.createElement('span'), {
            className: 'fallback', textContent: item.kind === 'server' ? '👥' : '💬'
          }));
        });
        button.append(image);
      } else {
        const fallback = document.createElement('span');
        fallback.className = 'fallback fluent';
        fallback.textContent = item.kind === 'action' ? '\uE710'
          : item.kind === 'directMessages' ? '\uE8BD' : '\uE716';
        button.append(fallback);
      }
      if (item.mentions) {
        const badge = document.createElement('span');
        badge.className = 'mention';
        badge.textContent = item.mentions > 99 ? '99+' : String(item.mentions);
        button.append(badge);
      }
      root.append(button);
    }
  };

  ipcRenderer.on('sidecord:rail-state', (_event, value) => {
    settings = value.settings || settings;
    items = Array.isArray(value.items) ? value.items : items;
    render();
  });
  ipcRenderer.send('sidecord:rail-ready');
});
