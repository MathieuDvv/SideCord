'use strict';

const fs = require('node:fs');
const path = require('node:path');

const ACCENTS = {
  automatic: ['#5865f2', '88 101 242'],
  blurple: ['#5865f2', '88 101 242'],
  blue: ['#0a84ff', '10 132 255'],
  purple: ['#af52de', '175 82 222'],
  pink: ['#ff2d55', '255 45 85'],
  green: ['#30d158', '48 209 88'],
  orange: ['#ff9f0a', '255 159 10'],
  white: ['#ffffff', '255 255 255']
};

const LAYOUTS = {
  full: {
    navigationPresentation: 'docked', composerMode: 'full', hideMemberList: false,
    hideAccountDock: false, simplifyHeader: false, compactMedia: false, reduceMotion: false
  },
  focus: {
    navigationPresentation: 'floating', composerMode: 'essential', hideMemberList: true,
    hideAccountDock: false, simplifyHeader: true, compactMedia: false, reduceMotion: false
  },
  reader: {
    navigationPresentation: 'hidden', composerMode: 'hidden', hideMemberList: true,
    hideAccountDock: true, simplifyHeader: true, compactMedia: false, reduceMotion: false
  }
};

function layoutOptions(settings) {
  return settings.discordLayoutMode === 'custom'
    ? settings.customDiscordLayoutOptions
    : LAYOUTS[settings.discordLayoutMode] || LAYOUTS.full;
}

function customCssValidationError(css) {
  const value = String(css || '');
  const lower = value.toLowerCase();
  const forbidden = ['@', '\\', '/*', '://', '//', 'data:', 'file:', 'blob:'];
  if (forbidden.some((fragment) => lower.includes(fragment))
    || /(^|[^a-z0-9_-])(url|image|image-set|-webkit-image-set|src)\s*\(/i.test(value)) {
    return 'Remote resources, @-rules, comments, URLs, and CSS escape sequences are not allowed.';
  }
  return null;
}

function configuration(settings) {
  const options = layoutOptions(settings);
  const intensity = Math.min(Math.max(Number(settings.themeIntensity) || 0, 0), 1);
  const accent = ACCENTS[settings.themeAccent] || ACCENTS.automatic;
  const attributes = {
    'data-sidecord-navigation': options.navigationPresentation,
    'data-sidecord-composer': options.composerMode,
    'data-sidecord-theme': settings.visualTheme === 'systemGlass' ? 'system-glass' : settings.visualTheme,
    'data-sidecord-accent': settings.themeAccent,
    'data-sidecord-color-scheme': settings.themeColorScheme,
    'data-sidecord-theme-intensity': String(intensity)
  };
  const optional = {
    'data-sidecord-hide-members': options.hideMemberList,
    'data-sidecord-hide-account-dock': options.hideAccountDock,
    'data-sidecord-simplify-header': options.simplifyHeader,
    'data-sidecord-compact-media': options.compactMedia,
    'data-sidecord-reduce-motion': options.reduceMotion,
    'data-sidecord-floating-rail': settings.floatingRailEnabled
      && options.navigationPresentation === 'floating'
  };
  for (const [key, enabled] of Object.entries(optional)) {
    if (enabled) attributes[key] = '';
  }
  return {
    attributes,
    variables: {
      '--sidecord-theme-intensity': String(intensity),
      '--sidecord-theme-strength': `${intensity * 100}%`,
      '--sidecord-accent-color': accent[0],
      '--sidecord-accent-rgb': accent[1]
    },
    options
  };
}

function compose(settings, resourcesDirectory) {
  const sections = [];
  const read = (name) => fs.readFileSync(path.join(resourcesDirectory, name), 'utf8').trim();
  if (settings.cssPreset === 'compact') sections.push(read('compact.css'));
  sections.push(read('layout-mods.css'), read('visual-themes.css'), read('windows-overrides.css'));
  if (settings.customCSSEnabled) {
    sections.push(customCssValidationError(settings.customCSS)
      ? '/* SideCord blocked unsafe custom CSS. */'
      : settings.customCSS.trim());
  }
  return sections.filter(Boolean).join('\n\n');
}

module.exports = { ACCENTS, LAYOUTS, layoutOptions, customCssValidationError, configuration, compose };
