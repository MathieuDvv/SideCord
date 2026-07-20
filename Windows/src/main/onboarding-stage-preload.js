'use strict';

const { ipcRenderer } = require('electron');

window.addEventListener('DOMContentLoaded', () => {
  const prompt = document.getElementById('signin');
  ipcRenderer.on('sidecord:onboarding-state', (_event, state) => {
    document.body.dataset.phase = state.phase;
    prompt.hidden = state.phase !== 'signIn';
  });
  document.getElementById('skip').addEventListener('click', () => {
    ipcRenderer.send('sidecord:onboarding-action', 'skip');
  });
  document.getElementById('backdrop').addEventListener('click', () => {
    ipcRenderer.send('sidecord:onboarding-action', 'backdrop');
  });
  ipcRenderer.send('sidecord:onboarding-ready');
});
