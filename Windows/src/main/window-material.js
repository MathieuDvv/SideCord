'use strict';

function resolveColorScheme(settings, nativeTheme) {
  if (settings.themeColorScheme === 'light' || settings.themeColorScheme === 'dark') {
    return settings.themeColorScheme;
  }
  return nativeTheme?.shouldUseDarkColors === false ? 'light' : 'dark';
}

function supportsMica(platform, systemVersion) {
  if (platform !== 'win32') return false;
  const parts = String(systemVersion || '').split('.').map(Number);
  return parts.length >= 3 && Number.isFinite(parts[2]) && parts[2] >= 22621;
}

function materialFor(settings, nativeTheme, platform = process.platform, systemVersion = '') {
  const scheme = resolveColorScheme(settings, nativeTheme);
  switch (settings.visualTheme) {
    case 'systemGlass': {
      const mica = supportsMica(platform, systemVersion);
      return {
        material: mica ? 'mica' : 'none',
        color: mica ? '#00000000' : (scheme === 'light' ? '#F7F8FC' : '#14171E')
      };
    }
    case 'oled':
      return { material: 'none', color: '#000000' };
    case 'soft':
      return { material: 'none', color: scheme === 'light' ? '#FFF9FB' : '#292631' };
    case 'discord':
    default:
      return { material: 'none', color: scheme === 'light' ? '#FFFFFF' : '#313338' };
  }
}

function applyWindowMaterial(window, settings, nativeTheme) {
  if (!window || window.isDestroyed()) return;
  const resolved = materialFor(
    settings,
    nativeTheme,
    process.platform,
    typeof process.getSystemVersion === 'function' ? process.getSystemVersion() : ''
  );
  if (process.platform === 'win32') window.setBackgroundMaterial(resolved.material);
  window.setBackgroundColor(resolved.color);
}

module.exports = { resolveColorScheme, supportsMica, materialFor, applyWindowMaterial };
