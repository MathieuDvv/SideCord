'use strict';

const { ipcRenderer } = require('electron');

window.addEventListener('DOMContentLoaded', () => {
  ipcRenderer.on('sidecord:glow', (_event, value) => {
    const glow = document.getElementById('glow');
    glow.className = '';
    glow.style.setProperty('--color', value.color);
    requestAnimationFrame(() => {
      glow.className = `${value.edge} ${value.strength} pulse`;
    });
  });
});
