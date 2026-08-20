import { describe, expect, test } from 'bun:test'
import { initialSelection, moveSelection, resizeSelection } from './selection'

describe('selection geometry', () => {
  test('keeps a moved region inside the stage', () => {
    const moved = moveSelection(initialSelection, 1, 1)

    expect(moved.x).toBeCloseTo(1 - initialSelection.width)
    expect(moved.y).toBeCloseTo(1 - initialSelection.height)
  })

  test('resizes from a handle without crossing the minimum size', () => {
    const resized = resizeSelection(initialSelection, 'topLeft', 1, 1, 0.1, 0.1)

    expect(resized.width).toBeCloseTo(0.1)
    expect(resized.height).toBeCloseTo(0.1)
  })
})
