'use strict';

const path = require('node:path');
const {
  app, BrowserWindow, Menu, Tray, nativeImage, globalShortcut,
  ipcMain, screen, session, shell, dialog, nativeTheme
} = require('electron');
const { SettingsStore } = require('./settings-store');
const { PanelController } = require('./panel-controller');
const { classify, isAuthenticationPopup, isAllowedPermissionOrigin } = require('./url-policy');
const { compose, configuration, customCssValidationError, layoutOptions } = require('./css-composer');
const { glowBounds, railBounds } = require('./panel-geometry');
const { validateRailItems } = require('./rail-model');
const { OnboardingController } = require('./onboarding-controller');
const { applyWindowMaterial } = require('./window-material');

const DISCORD_URL = 'https://discord.com/app';
const resourcesDirectory = path.join(__dirname, '..', 'web');
const preloadPath = path.join(__dirname, 'preload.js');
const iconPath = path.join(__dirname, '..', '..', 'assets', 'icon.png');

let store;
let panel;
let tray;
let glowWindow;
let glowTimer;
let railWindow;
let railItems = [];
let onboarding;
let onboardingScheduled = false;
let quitting = false;
let shortcutErrors = {};

if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.on('second-instance', () => panel?.reveal(null, true));
}

app.setAppUserModelId('com.sidecord.windows');

function discordSession() {
  return session.fromPartition('persist:sidecord-discord');
}

function makeMainWindow() {
  const window = new BrowserWindow({
    show: false,
    width: 420,
    height: 800,
    minWidth: 320,
    minHeight: 300,
    frame: false,
    transparent: false,
    backgroundColor: '#111318',
    ...(process.platform === 'win32' ? { backgroundMaterial: 'mica' } : {}),
    roundedCorners: true,
    resizable: true,
    movable: false,
    minimizable: false,
    maximizable: false,
    fullscreenable: false,
    alwaysOnTop: true,
    skipTaskbar: true,
    autoHideMenuBar: true,
    icon: iconPath,
    webPreferences: {
      preload: preloadPath,
      partition: 'persist:sidecord-discord',
      sandbox: true,
      contextIsolation: true,
      nodeIntegration: false,
      webviewTag: false,
      spellcheck: true,
      backgroundThrottling: false
    }
  });

  window.setAlwaysOnTop(true, 'floating');
  applyWindowMaterial(window, store.value, nativeTheme);
  window.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  window.on('close', (event) => {
    if (!quitting) {
      event.preventDefault();
      panel.retract();
    }
  });

  installNavigationPolicy(window.webContents, true);
  window.webContents.on('did-finish-load', () => {
    sendRendererState(window);
    if (!store.value.onboardingCompleted && !onboardingScheduled
      && !process.argv.includes('--diagnose-settings')
      && !process.argv.includes('--diagnose-rail')) {
      onboardingScheduled = true;
      setTimeout(() => onboarding?.start(), 250);
    }
  });
  window.webContents.on('did-navigate', (_event, url) => onboarding?.navigationChanged(url));
  window.webContents.on('did-navigate-in-page', (_event, url) => onboarding?.navigationChanged(url));
  window.webContents.on('did-fail-load', (_event, code, description, validatedUrl, isMainFrame) => {
    if (isMainFrame && code !== -3) {
      window.webContents.send('sidecord:load-error', { description, url: validatedUrl });
    }
  });
  window.webContents.on('render-process-gone', () => {
    setTimeout(() => {
      if (!window.isDestroyed()) window.loadURL(DISCORD_URL);
    }, 500);
  });
  window.loadURL(DISCORD_URL);
  return window;
}

function createRailWindow() {
  railWindow = new BrowserWindow({
    show: false,
    width: 76,
    height: 600,
    minWidth: 76,
    maxWidth: 76,
    frame: false,
    transparent: process.platform !== 'win32',
    backgroundColor: '#00000000',
    ...(process.platform === 'win32' ? { backgroundMaterial: 'mica' } : {}),
    alwaysOnTop: true,
    skipTaskbar: true,
    resizable: false,
    movable: false,
    minimizable: false,
    maximizable: false,
    fullscreenable: false,
    hasShadow: false,
    webPreferences: {
      preload: path.join(__dirname, 'rail-preload.js'),
      sandbox: true,
      contextIsolation: true,
      nodeIntegration: false
    }
  });
  railWindow.setAlwaysOnTop(true, 'floating');
  applyWindowMaterial(railWindow, store.value, nativeTheme);
  railWindow.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  railWindow.loadFile(path.join(__dirname, '..', 'renderer', 'rail.html'));
}

function railShouldBeVisible() {
  if (process.argv.includes('--diagnose-rail')) return Boolean(panel?.visible);
  const onboardingBlocksRail = onboarding?.isActive() && onboarding.phase !== 'configuration';
  return Boolean(panel?.visible && !panel.maximized && !onboardingBlocksRail
    && store.value.floatingRailEnabled
    && layoutOptions(store.value).navigationPresentation !== 'docked');
}

function sendRailState() {
  if (!railWindow || railWindow.isDestroyed() || railWindow.webContents.isLoadingMainFrame()) return;
  railWindow.webContents.send('sidecord:rail-state', { settings: store.value, items: railItems });
}

function updateRailWindow() {
  if (!railWindow || railWindow.isDestroyed()) return;
  if (!railShouldBeVisible() || !panel?.window || panel.window.isDestroyed()) {
    railWindow.hide();
    return;
  }
  const sidebar = panel.window.getBounds();
  const display = screen.getDisplayMatching(sidebar);
  const bounds = railBounds(sidebar, display.workArea, store.value.sidebarEdge);
  if (!bounds) {
    railWindow.hide();
    return;
  }
  railWindow.setBounds(bounds, false);
  railWindow.showInactive();
  sendRailState();
}

function installNavigationPolicy(contents, isMainWindow) {
  contents.setWindowOpenHandler(({ url }) => {
    const decision = classify(url);
    const authenticationPopup = isAuthenticationPopup(url);
    if (isMainWindow && decision === 'allow' && !authenticationPopup) {
      contents.loadURL(url);
      return { action: 'deny' };
    }
    if (!authenticationPopup) {
      return { action: 'deny' };
    }
    return {
      action: 'allow',
      overrideBrowserWindowOptions: {
        width: 560,
        height: 720,
        autoHideMenuBar: true,
        parent: panel?.window || undefined,
        modal: false,
        webPreferences: {
          sandbox: true,
          contextIsolation: true,
          nodeIntegration: false,
          partition: 'persist:sidecord-discord'
        }
      }
    };
  });
  if (isMainWindow) {
    contents.on('did-create-window', (childWindow) => installAuthenticationPopupPolicy(childWindow.webContents));
  }
  contents.on('will-navigate', (event, url) => {
    const decision = classify(url);
    if (decision === 'allow') return;
    event.preventDefault();
  });
}

function installAuthenticationPopupPolicy(contents) {
  const guardNavigation = (event, url) => {
    try {
      const parsed = new URL(url);
      if (parsed.protocol === 'https:' || parsed.protocol === 'about:') return;
    } catch { /* Cancel malformed popup navigation. */ }
    event.preventDefault();
  };
  contents.on('will-navigate', guardNavigation);
  contents.on('will-redirect', guardNavigation);
  contents.setWindowOpenHandler(({ url }) => {
    try {
      if (new URL(url).protocol === 'https:') contents.loadURL(url);
    } catch { /* Ignore malformed nested popup targets. */ }
    return { action: 'deny' };
  });
}

function configureSession() {
  const persistentSession = discordSession();
  persistentSession.setPermissionCheckHandler((_webContents, permission, requestingOrigin) => {
    return ['media', 'notifications', 'fullscreen'].includes(permission)
      && isAllowedPermissionOrigin(requestingOrigin);
  });
  persistentSession.setPermissionRequestHandler((webContents, permission, callback, details) => {
    const origin = details.requestingUrl || webContents.getURL();
    callback(['media', 'notifications', 'fullscreen'].includes(permission)
      && isAllowedPermissionOrigin(origin));
  });
  persistentSession.on('will-download', (_event, item, webContents) => {
    item.pause();
    const suggested = item.getFilename().replace(/[<>:"/\\|?*\x00-\x1f]/g, '_');
    dialog.showSaveDialog(panel?.window || BrowserWindow.fromWebContents(webContents), {
      title: 'Save Discord download',
      defaultPath: suggested
    }).then(({ canceled, filePath }) => {
      if (canceled || !filePath) item.cancel();
      else {
        item.setSavePath(filePath);
        item.resume();
      }
    });
  });
}

function registerShortcuts() {
  globalShortcut.unregisterAll();
  shortcutErrors = {};
  const entries = [
    ['shortcut', store.value.shortcut, () => panel.toggle(true)],
    ['navigationShortcut', store.value.navigationShortcut, () => {
      if (!panel.visible) panel.reveal(null, true);
      panel.window?.webContents.send('sidecord:toggle-navigation');
    }]
  ];
  for (const [key, accelerator, handler] of entries) {
    if (!globalShortcut.register(accelerator, handler)) {
      shortcutErrors[key] = `Windows or another app is already using ${accelerator}.`;
    }
  }
}

function applyLoginItemSetting() {
  if (process.platform !== 'win32') return;
  app.setLoginItemSettings({
    openAtLogin: store.value.launchAtLoginEnabled,
    path: process.execPath,
    args: app.isPackaged ? [] : [app.getAppPath()]
  });
}

function sendRendererState(window = panel?.window) {
  if (!window || window.isDestroyed()) return;
  let css = '';
  try {
    css = compose(store.value, resourcesDirectory);
  } catch (error) {
    console.error('Unable to compose SideCord CSS:', error);
  }
  window.webContents.send('sidecord:state', {
    settings: store.value,
    configuration: configuration(store.value),
    css,
    shortcutErrors
  });
  updateRailWindow();
}

function settingsChanged(previous) {
  if (previous.shortcut !== store.value.shortcut
    || previous.navigationShortcut !== store.value.navigationShortcut) registerShortcuts();
  if (previous.launchAtLoginEnabled !== store.value.launchAtLoginEnabled) applyLoginItemSetting();
  if (previous.sidebarEdge !== store.value.sidebarEdge
    || previous.sidebarInset !== store.value.sidebarInset
    || previous.sidebarWidth !== store.value.sidebarWidth) panel.reposition();
  if (previous.visualTheme !== store.value.visualTheme
    || previous.themeColorScheme !== store.value.themeColorScheme) {
    applyWindowMaterial(panel?.window, store.value, nativeTheme);
    applyWindowMaterial(railWindow, store.value, nativeTheme);
  }
  sendRendererState();
  sendRailState();
  onboarding?.settingsDidChange();
  rebuildTray();
}

function handleAction(action) {
  const window = panel?.window;
  switch (action) {
    case 'toggle': panel.toggle(true); break;
    case 'hide': panel.retract(); break;
    case 'pin': panel.togglePin(); sendRendererState(); rebuildTray(); break;
    case 'toggle-rail': {
      const previous = store.value;
      store.update({ floatingRailEnabled: !store.value.floatingRailEnabled });
      settingsChanged(previous);
      break;
    }
    case 'maximize': panel.toggleMaximize(); sendRendererState(); rebuildTray(); break;
    case 'reload': window?.reload(); break;
    case 'back': if (window?.webContents.canGoBack()) window.webContents.goBack(); break;
    case 'forward': if (window?.webContents.canGoForward()) window.webContents.goForward(); break;
    case 'settings': panel.reveal(null, true); window?.webContents.send('sidecord:show-settings'); break;
    case 'onboarding': onboarding?.start(); break;
    case 'quit': quitting = true; app.quit(); break;
    default: break;
  }
}

function rebuildTray() {
  if (!tray) return;
  const menu = Menu.buildFromTemplate([
    { label: panel?.visible ? 'Hide SideCord' : 'Show SideCord', click: () => handleAction('toggle') },
    { label: `Shortcut: ${store.value.shortcut}`, enabled: false },
    ...(shortcutErrors.shortcut ? [{ label: shortcutErrors.shortcut, enabled: false }] : []),
    { type: 'separator' },
    { label: 'Pin Sidebar', type: 'checkbox', checked: store.value.isPinned, click: () => handleAction('pin') },
    { label: panel?.maximized ? 'Restore Sidebar' : 'Maximize Sidebar', click: () => handleAction('maximize') },
    { label: 'Reload Discord', click: () => handleAction('reload') },
    { type: 'separator' },
    { label: 'Settings…', click: () => handleAction('settings') },
    { label: 'Welcome to SideCord…', click: () => handleAction('onboarding') },
    { type: 'separator' },
    { label: 'Quit SideCord', click: () => handleAction('quit') }
  ]);
  tray.setContextMenu(menu);
  tray.setToolTip('SideCord');
}

function createTray() {
  let image = nativeImage.createFromPath(iconPath);
  if (!image.isEmpty()) image = image.resize({ width: 20, height: 20 });
  tray = new Tray(image);
  tray.on('click', () => handleAction('toggle'));
  rebuildTray();
}

function createGlowWindow() {
  glowWindow = new BrowserWindow({
    show: false,
    frame: false,
    transparent: true,
    backgroundColor: '#00000000',
    alwaysOnTop: true,
    skipTaskbar: true,
    focusable: false,
    resizable: false,
    movable: false,
    hasShadow: false,
    webPreferences: {
      preload: path.join(__dirname, 'glow-preload.js'),
      sandbox: true,
      contextIsolation: true,
      nodeIntegration: false
    }
  });
  glowWindow.setIgnoreMouseEvents(true);
  glowWindow.setAlwaysOnTop(true, 'screen-saver');
  glowWindow.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  glowWindow.loadFile(path.join(__dirname, '..', 'renderer', 'glow.html'));
}

function showAttentionGlow(force = false, requestedDisplay = null) {
  if ((!force && (!store.value.notificationGlowEnabled || panel.visible)) || !glowWindow) return;
  const display = requestedDisplay || screen.getDisplayNearestPoint(screen.getCursorScreenPoint());
  const widths = { subtle: 58, normal: 72, strong: 136 };
  const accents = {
    automatic: '#5865f2', blurple: '#5865f2', blue: '#0a84ff', purple: '#af52de',
    pink: '#ff2d55', green: '#30d158', orange: '#ff9f0a', white: '#ffffff'
  };
  const colorKey = store.value.attentionGlowColor === 'followTheme'
    ? store.value.themeAccent : store.value.attentionGlowColor;
  glowWindow.setBounds(glowBounds(display.bounds, store.value.sidebarEdge, widths[store.value.attentionGlowStrength]));
  glowWindow.showInactive();
  glowWindow.webContents.send('sidecord:glow', {
    edge: store.value.sidebarEdge,
    color: accents[colorKey] || accents.automatic,
    strength: store.value.attentionGlowStrength
  });
  if (glowTimer) clearTimeout(glowTimer);
  glowTimer = setTimeout(() => glowWindow?.hide(), 1450);
}

function installIpc() {
  ipcMain.on('sidecord:get-state', (event) => {
    event.returnValue = { settings: store.value, shortcutErrors };
  });
  ipcMain.on('sidecord:renderer-ready', (event) => {
    const window = BrowserWindow.fromWebContents(event.sender);
    if (window === panel?.window) sendRendererState(window);
  });
  ipcMain.handle('sidecord:update-settings', (_event, patch) => {
    if (!patch || typeof patch !== 'object' || Array.isArray(patch)) return { ok: false };
    if (typeof patch.customCSS === 'string') {
      const error = customCssValidationError(patch.customCSS);
      if (error && patch.customCSSEnabled !== false) return { ok: false, error };
    }
    const previous = store.value;
    const nextPatch = Object.hasOwn(patch, 'sidebarWidth')
      ? { ...patch, displayWidths: {} }
      : patch;
    store.update(nextPatch);
    settingsChanged(previous);
    return { ok: true, settings: store.value, shortcutErrors };
  });
  ipcMain.handle('sidecord:reset-settings', () => {
    const previous = store.value;
    store.reset();
    settingsChanged(previous);
    return { ok: true, settings: store.value, shortcutErrors };
  });
  ipcMain.on('sidecord:action', (_event, action) => handleAction(action));
  ipcMain.on('sidecord:attention', (event) => {
    if (event.sender === panel?.window?.webContents) showAttentionGlow();
  });
  ipcMain.on('sidecord:rail-ready', (event) => {
    if (event.sender === railWindow?.webContents) sendRailState();
  });
  ipcMain.on('sidecord:rail-state', (event, items) => {
    if (event.sender !== panel?.window?.webContents) return;
    if (process.argv.includes('--diagnose-rail')) return;
    const validated = validateRailItems(items);
    if (!validated) return;
    railItems = validated;
    sendRailState();
  });
  ipcMain.on('sidecord:rail-activate', (event, id) => {
    if (event.sender !== railWindow?.webContents) return;
    if (typeof id !== 'string' || !railItems.some((item) => item.id === id)) return;
    panel?.window?.webContents.send('sidecord:activate-rail', id);
    panel?.window?.focus();
  });
  ipcMain.on('sidecord:open-external', (event, url) => {
    if (event.sender !== panel?.window?.webContents) return;
    if (classify(url) === 'external' && !isAuthenticationPopup(url)) shell.openExternal(url);
  });
  ipcMain.on('sidecord:onboarding-ready', (event) => {
    if (onboarding?.owns(event.sender)) onboarding.settingsDidChange();
  });
  ipcMain.on('sidecord:onboarding-action', (event, action) => {
    if (onboarding?.owns(event.sender) && typeof action === 'string') onboarding.handleAction(action);
  });
  ipcMain.on('sidecord:onboarding-setting', (event, payload) => {
    if (!onboarding?.owns(event.sender) || !payload || typeof payload !== 'object') return;
    onboarding.updateSetting(payload.key, payload.value);
  });
}

function completeOnboarding() {
  if (!store.value.onboardingCompleted) {
    const previous = store.value;
    store.update({ onboardingCompleted: true });
    settingsChanged(previous);
  }
  setTimeout(() => panel.retract(), 280);
}

app.whenReady().then(() => {
  store = new SettingsStore(path.join(app.getPath('userData'), 'settings.json'));
  configureSession();
  installIpc();
  panel = new PanelController({
    BrowserWindow,
    screen,
    settings: store,
    createWindow: makeMainWindow,
    onVisibilityChanged: () => {
      rebuildTray();
      updateRailWindow();
    },
    additionalHoverBounds: () => [
      railWindow?.isVisible() ? railWindow.getBounds() : null,
      onboarding?.companionBounds()
    ],
    automaticBehaviorSuppressed: () => onboarding?.isActive() || false
  });
  panel.start();
  const companionWindowsChanged = () => {
    updateRailWindow();
    onboarding?.reposition();
  };
  panel.window.on('move', companionWindowsChanged);
  panel.window.on('resize', companionWindowsChanged);
  createGlowWindow();
  createRailWindow();
  onboarding = new OnboardingController({
    BrowserWindow,
    screen,
    panel,
    settings: store,
    onSettingsPatch: (patch) => {
      const previous = store.value;
      store.update(patch);
      settingsChanged(previous);
    },
    onComplete: completeOnboarding,
    onGlow: showAttentionGlow
  });
  createTray();
  registerShortcuts();
  applyLoginItemSetting();
  nativeTheme.on('updated', () => {
    if (store.value.themeColorScheme !== 'system') return;
    applyWindowMaterial(panel?.window, store.value, nativeTheme);
    applyWindowMaterial(railWindow, store.value, nativeTheme);
  });
  if (store.value.onboardingCompleted || process.argv.includes('--diagnose-settings')
    || process.argv.includes('--diagnose-rail')) {
    panel.reveal(null, true);
  }
  if (process.argv.includes('--diagnose') && !process.argv.includes('--diagnose-settings')) {
    if (!process.argv.includes('--diagnose-rail')) {
      setTimeout(() => onboarding?.start(), 300);
    }
    const diagnosticSkip = setInterval(() => {
      if (onboarding?.phase === 'signIn') {
        clearInterval(diagnosticSkip);
        onboarding.handleAction('skip');
      }
    }, 100);
  }
  if (process.argv.includes('--diagnose-settings')) {
    setTimeout(async () => {
      const window = panel.window;
      await window.webContents.executeJavaScript(`(() => {
        const shell = document.createElement('div');
        shell.className = 'standardSidebarView_probe';
        shell.innerHTML = '<div class="sidebarRegion_probe"><nav class="sidebar_probe"><div class="side_probe"><button class="item_probe selected_probe" role="tab" aria-selected="true">Account</button><div class="header_probe">App Settings</div><button class="item_probe" role="tab">Appearance</button><button class="item_probe danger_probe" data-list-item-id="logout">Log Out</button></div></nav></div><div class="contentRegion_probe"><main class="contentColumn_probe"><div id="discord-settings-probe">Discord Settings<select class="discord_select_probe"><option>Native</option></select><input class="discord_input_probe" value="Native"></div></main></div>';
        document.body.append(shell);
      })()`);
      window.webContents.send('sidecord:show-settings');
      setTimeout(() => window.webContents.executeJavaScript(
        `document.querySelector('[data-sidecord-settings-nav="theme"]')?.click()`
      ), 500);
    }, 900);
  }
  if (process.argv.includes('--diagnose-rail')) {
    setTimeout(() => {
      panel.reveal(null, true);
      panel.maximized = true;
      railItems = validateRailItems([
        { id: 'direct-messages', title: 'Direct Messages', icon: null, kind: 'directMessages', selected: true, unread: false, mentions: null },
        { id: 'server:123', title: 'SideCord', icon: null, kind: 'server', selected: false, unread: true, mentions: 3 }
      ]);
      updateRailWindow();
      const diagnosticSettings = { ...store.value, visualTheme: 'oled', themeColorScheme: 'dark' };
      applyWindowMaterial(railWindow, diagnosticSettings, nativeTheme);
      railWindow.webContents.send('sidecord:rail-state', { settings: diagnosticSettings, items: railItems });
    }, 900);
  }
  if (process.argv.includes('--diagnose')) {
    setTimeout(async () => {
      const window = panel.window;
      let renderer = null;
      let railRenderer = null;
      try {
        renderer = await window?.webContents.executeJavaScript(`({
          controls: !!document.getElementById('sidecord-controls'),
          styleBytes: document.getElementById('sidecord-injected-css')?.textContent.length || 0,
          onboarding: Boolean(document.getElementById('sidecord-onboarding-overlay')
            && !document.getElementById('sidecord-onboarding-overlay').hidden),
          navigation: document.documentElement.getAttribute('data-sidecord-navigation'),
          railControl: !!document.querySelector('[data-sidecord-control="rail"]'),
          integratedSettingsNav: !!document.querySelector('[data-sidecord-settings-nav]'),
          integratedSettingsNavCount: document.querySelectorAll('[data-sidecord-settings-nav]').length,
          integratedSettingsPage: !!document.querySelector('[data-sidecord-settings-page]:not([hidden])'),
          settingsCategory: document.querySelector('[data-sidecord-settings-page]')?.dataset.sidecordSelectedPage || null,
          visibleSettingsSections: [...document.querySelectorAll('[data-sidecord-settings-page] section[data-sidecord-page]')]
            .filter(section => getComputedStyle(section).display !== 'none').map(section => section.dataset.sidecordPage),
          nativeStyledInputs: document.querySelectorAll('[data-sidecord-native-input-style]').length,
          micaLabel: !!document.querySelector('option[value="systemGlass"]')?.textContent.includes('Mica')
        })`);
      } catch (error) {
        renderer = { error: error.message };
      }
      if (railWindow?.isVisible()) {
        try {
          railRenderer = await railWindow.webContents.executeJavaScript(`({
            itemCount: document.querySelectorAll('.rail-item').length,
            selectedCount: document.querySelectorAll('.rail-item.selected').length,
            mentionText: document.querySelector('.mention')?.textContent || '',
            theme: document.documentElement.dataset.theme,
            railBackground: getComputedStyle(document.getElementById('rail')).backgroundColor
          })`);
        } catch (error) {
          railRenderer = { error: error.message };
        }
      }
      console.log(JSON.stringify({
        visible: panel.visible,
        windowVisible: window?.isVisible(),
        windowFocused: window?.isFocused(),
        bounds: window?.getBounds(),
        url: window?.webContents.getURL(),
        loading: window?.webContents.isLoadingMainFrame(),
        renderer,
        railRenderer,
        onboardingPhase: onboarding?.phase,
        onboardingStageVisible: onboarding?.stage?.isVisible(),
        onboardingCompanionVisible: onboarding?.companion?.isVisible(),
        onboardingCompanionBounds: onboarding?.companionBounds(),
        railWindowVisible: railWindow?.isVisible()
      }));
      quitting = true;
      app.quit();
    }, process.argv.includes('--diagnose-hold')
      ? 30000
      : (process.argv.includes('--diagnose-settings') || process.argv.includes('--diagnose-rail'))
        ? 3000 : 6000);
  }
});

app.on('activate', () => panel?.reveal(null, true));
app.on('will-quit', () => {
  quitting = true;
  globalShortcut.unregisterAll();
  panel?.stop();
});
app.on('window-all-closed', (event) => event.preventDefault?.());
