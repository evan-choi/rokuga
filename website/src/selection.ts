export type SelectionRegion = {
  x: number
  y: number
  width: number
  height: number
}

export type SelectionHandle =
  | 'topLeft'
  | 'top'
  | 'topRight'
  | 'left'
  | 'right'
  | 'bottomLeft'
  | 'bottom'
  | 'bottomRight'

export const initialSelection: SelectionRegion = {
  x: 0.29,
  y: 0.24,
  width: 0.42,
  height: 0.435,
}

export const mobileInitialSelection: SelectionRegion = {
  x: 0.12,
  y: 0.22,
  width: 0.76,
  height: 0.4,
}

const clamp = (value: number, minimum: number, maximum: number) => (
  Math.min(Math.max(value, minimum), maximum)
)

export function moveSelection(region: SelectionRegion, dx: number, dy: number): SelectionRegion {
  return {
    ...region,
    x: clamp(region.x + dx, 0, 1 - region.width),
    y: clamp(region.y + dy, 0, 1 - region.height),
  }
}

export function resizeSelection(
  region: SelectionRegion,
  handle: SelectionHandle,
  dx: number,
  dy: number,
  minimumWidth: number,
  minimumHeight: number,
): SelectionRegion {
  let left = region.x
  let top = region.y
  let right = region.x + region.width
  let bottom = region.y + region.height

  if (handle === 'topLeft' || handle === 'left' || handle === 'bottomLeft') {
    left = clamp(left + dx, 0, right - minimumWidth)
  }
  if (handle === 'topRight' || handle === 'right' || handle === 'bottomRight') {
    right = clamp(right + dx, left + minimumWidth, 1)
  }
  if (handle === 'topLeft' || handle === 'top' || handle === 'topRight') {
    top = clamp(top + dy, 0, bottom - minimumHeight)
  }
  if (handle === 'bottomLeft' || handle === 'bottom' || handle === 'bottomRight') {
    bottom = clamp(bottom + dy, top + minimumHeight, 1)
  }

  return { x: left, y: top, width: right - left, height: bottom - top }
}
