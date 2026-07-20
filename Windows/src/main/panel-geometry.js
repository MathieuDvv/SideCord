'use strict';

const MINIMUM_WIDTH = 320;
const MAXIMUM_DISPLAY_FRACTION = 0.8;
const HIDDEN_OVERSHOOT = 4;
const RAIL_WIDTH = 76;
const RAIL_GAP = 12;
const RAIL_VERTICAL_INSET = 12;

function finite(value, fallback) {
  return Number.isFinite(value) ? value : fallback;
}

function constrainedInset(requestedInset, workArea) {
  const maximum = Math.max(0, (Math.min(workArea.width, workArea.height) - 1) / 2);
  return Math.min(Math.max(finite(requestedInset, 0), 0), maximum);
}

function constrainedWidth(requestedWidth, workArea, inset = 0) {
  const safeInset = constrainedInset(inset, workArea);
  const insetAvailableWidth = Math.max(1, workArea.width - safeInset * 2);
  const maximum = Math.max(1, Math.min(workArea.width * MAXIMUM_DISPLAY_FRACTION, insetAvailableWidth));
  const minimum = Math.min(MINIMUM_WIDTH, maximum);
  return Math.min(Math.max(finite(requestedWidth, 420), minimum), maximum);
}

function sidebarBounds(workArea, edge, requestedWidth, inset = 0) {
  const safeInset = constrainedInset(inset, workArea);
  const width = Math.round(constrainedWidth(requestedWidth, workArea, safeInset));
  const x = edge === 'left'
    ? workArea.x + safeInset
    : workArea.x + workArea.width - width - safeInset;
  return {
    x: Math.round(x),
    y: Math.round(workArea.y + safeInset),
    width,
    height: Math.max(1, Math.round(workArea.height - safeInset * 2))
  };
}

function hiddenBounds(visibleBounds, displayBounds, edge) {
  return {
    ...visibleBounds,
    x: Math.round(edge === 'left'
      ? displayBounds.x - visibleBounds.width - HIDDEN_OVERSHOOT
      : displayBounds.x + displayBounds.width + HIDDEN_OVERSHOOT)
  };
}

function glowBounds(displayBounds, edge, requestedWidth = 72) {
  const width = Math.round(Math.min(Math.max(1, finite(requestedWidth, 72)), Math.max(1, displayBounds.width)));
  return {
    x: edge === 'left' ? displayBounds.x : displayBounds.x + displayBounds.width - width,
    y: displayBounds.y,
    width,
    height: Math.max(1, displayBounds.height)
  };
}

function railBounds(sidebar, workArea, edge, requestedWidth = RAIL_WIDTH, gap = RAIL_GAP) {
  if (!sidebar || sidebar.width < 1 || sidebar.height < 1) return null;
  const safeGap = Math.max(0, finite(gap, 0));
  const availableWidth = edge === 'right'
    ? sidebar.x - safeGap - workArea.x
    : workArea.x + workArea.width - (sidebar.x + sidebar.width) - safeGap;
  const width = Math.min(Math.max(0, finite(requestedWidth, RAIL_WIDTH)), Math.max(0, availableWidth));
  if (width < 1) return null;
  const inset = Math.min(RAIL_VERTICAL_INSET, Math.max(0, (sidebar.height - 1) / 2));
  const y = Math.max(workArea.y, sidebar.y + inset);
  const bottom = Math.min(workArea.y + workArea.height, sidebar.y + sidebar.height - inset);
  if (bottom <= y) return null;
  return {
    x: Math.round(edge === 'right' ? sidebar.x - safeGap - width : sidebar.x + sidebar.width + safeGap),
    y: Math.round(y), width: Math.round(width), height: Math.round(bottom - y)
  };
}

function onboardingCompanionBounds(sidebar, workArea, edge, size = { width: 430, height: 650 }) {
  const width = Math.min(Math.max(1, finite(size.width, 430)), Math.max(1, workArea.width - 24));
  const height = Math.min(Math.max(1, finite(size.height, 650)), Math.max(1, workArea.height - 24));
  const preferredX = edge === 'right'
    ? sidebar.x - 18 - width
    : sidebar.x + sidebar.width + 18;
  const fallbackX = edge === 'right'
    ? sidebar.x - width * 0.72
    : sidebar.x + sidebar.width - width * 0.28;
  const clampX = (x) => Math.min(Math.max(x, workArea.x + 12), workArea.x + workArea.width - width - 12);
  let x = clampX(preferredX);
  const y = Math.min(
    Math.max(sidebar.y + (sidebar.height - height) / 2, workArea.y + 12),
    workArea.y + workArea.height - height - 12
  );
  const intersects = x < sidebar.x + sidebar.width && x + width > sidebar.x
    && y < sidebar.y + sidebar.height && y + height > sidebar.y;
  if (intersects) x = clampX(fallbackX);
  return { x: Math.round(x), y: Math.round(y), width: Math.round(width), height: Math.round(height) };
}

function containsPoint(bounds, point, padding = 0) {
  return point.x >= bounds.x - padding
    && point.x <= bounds.x + bounds.width + padding
    && point.y >= bounds.y - padding
    && point.y <= bounds.y + bounds.height + padding;
}

function isEdgeExposed(display, edge, y, displays) {
  const sample = {
    x: edge === 'left' ? display.bounds.x - 1 : display.bounds.x + display.bounds.width + 1,
    y
  };
  return !displays.some((candidate) => candidate.id !== display.id && containsPoint(candidate.bounds, sample));
}

module.exports = {
  MINIMUM_WIDTH,
  MAXIMUM_DISPLAY_FRACTION,
  RAIL_WIDTH,
  RAIL_GAP,
  constrainedInset,
  constrainedWidth,
  sidebarBounds,
  hiddenBounds,
  glowBounds,
  railBounds,
  onboardingCompanionBounds,
  containsPoint,
  isEdgeExposed
};
