import { describe, expect, test } from 'bun:test'
import { matchLanguage, selectLanguage } from './i18n'

describe('matchLanguage', () => {
  const cases = [
    ['ko-KR', 'ko'],
    ['en-US', 'en'],
    ['ja-JP', 'ja'],
    ['zh-CN', 'zh-Hans'],
    ['zh-SG', 'zh-Hans'],
    ['zh-Hans', 'zh-Hans'],
    ['zh-TW', 'en'],
    ['fr-FR', 'en'],
  ] as const

  test.each(cases)('%s maps to %s', (locale, expected) => {
    expect(matchLanguage([locale])).toBe(expected)
  })

  test('uses the first supported browser language', () => {
    expect(matchLanguage(['fr-FR', 'ja-JP', 'ko-KR'])).toBe('ja')
  })
})

describe('selectLanguage', () => {
  test('prefers a saved selection over browser languages', () => {
    expect(selectLanguage('ko', ['ja-JP'])).toBe('ko')
  })

  test('ignores an invalid saved selection', () => {
    expect(selectLanguage('fr', ['zh-CN'])).toBe('zh-Hans')
  })
})
