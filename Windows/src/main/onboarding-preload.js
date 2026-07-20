'use strict';

const { ipcRenderer } = require('electron');

window.addEventListener('DOMContentLoaded', () => {
  const steps = [...document.querySelectorAll('[data-step]')];
  const progress = [...document.querySelectorAll('.progress span')];
  const eyebrow = document.getElementById('eyebrow');
  const title = document.getElementById('title');
  const back = document.getElementById('back');
  const next = document.getElementById('next');
  const headings = [
    ['01 · Placement', 'Choose your edge'],
    ['02 · Layout', 'Shape your Discord'],
    ['03 · Appearance', 'Make it feel yours'],
    ['04 · Ready', 'You’re all set']
  ];
  let currentState;

  const render = (state) => {
    currentState = state;
    const { step, settings } = state;
    eyebrow.textContent = headings[step][0];
    title.textContent = headings[step][1];
    steps.forEach((node, index) => { node.hidden = index !== step; });
    progress.forEach((node, index) => node.classList.toggle('active', index <= step));
    back.hidden = step === 0;
    next.textContent = step === 3 ? 'Finish' : 'Continue';
    document.querySelectorAll('[data-setting]').forEach((input) => {
      const key = input.dataset.setting;
      if (!(key in settings)) return;
      if (input.type === 'checkbox') input.checked = Boolean(settings[key]);
      else input.value = String(settings[key]);
    });
    document.querySelectorAll('[data-edge]').forEach((node) => {
      node.classList.toggle('selected', node.dataset.edge === settings.sidebarEdge);
    });
    document.getElementById('edge-card').className = `edge-card ${settings.sidebarEdge}`;
    document.getElementById('ready-edge').textContent = settings.sidebarEdge;
    document.documentElement.style.setProperty('--accent', {
      automatic: '#5865f2', blurple: '#5865f2', blue: '#0a84ff', purple: '#af52de',
      pink: '#ff2d55', green: '#30d158', orange: '#ff9f0a', white: '#ffffff'
    }[settings.themeAccent] || '#5865f2');
  };

  document.addEventListener('change', (event) => {
    const input = event.target.closest?.('[data-setting]');
    if (!input) return;
    ipcRenderer.send('sidecord:onboarding-setting', {
      key: input.dataset.setting,
      value: input.type === 'checkbox' ? input.checked : input.value
    });
  });
  document.addEventListener('click', (event) => {
    const edge = event.target.closest?.('[data-edge]');
    if (edge) ipcRenderer.send('sidecord:onboarding-setting', { key: 'sidebarEdge', value: edge.dataset.edge });
  });
  back.addEventListener('click', () => ipcRenderer.send('sidecord:onboarding-action', 'back'));
  next.addEventListener('click', () => ipcRenderer.send(
    'sidecord:onboarding-action', currentState?.step === 3 ? 'finish' : 'next'
  ));
  window.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') ipcRenderer.send('sidecord:onboarding-action', 'finish');
  });
  ipcRenderer.on('sidecord:onboarding-state', (_event, state) => render(state));
  ipcRenderer.send('sidecord:onboarding-ready');
});
