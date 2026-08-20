import { describe, expect, test } from 'bun:test'

const websiteUrl = 'https://evan-choi.github.io/rokuga/'

describe('crawler metadata', () => {
  test('publishes the canonical URL and crawlable product copy', async () => {
    const index = await Bun.file(new URL('../index.html', import.meta.url)).text()
    const robots = await Bun.file(new URL('../public/robots.txt', import.meta.url)).text()
    const sitemap = await Bun.file(new URL('../public/sitemap.xml', import.meta.url)).text()
    const llms = await Bun.file(new URL('../public/llms.txt', import.meta.url)).text()
    const structuredDataSource = index.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/)?.[1]

    expect(index).toContain(`<link rel="canonical" href="${websiteUrl}"`)
    expect(structuredDataSource).toBeDefined()
    expect(JSON.parse(structuredDataSource!)).toMatchObject({
      '@type': 'SoftwareApplication',
      name: 'Rokuga',
      url: websiteUrl,
    })
    expect(index).toContain('Rokuga is a free, native, open-source screen recorder for Mac that records at display-matched frame rates, with H.265 and resolutions up to 5K.')
    expect(index).toContain('Rokuga is coming to the Mac App Store and Homebrew.')
    expect(robots).toContain(`Sitemap: ${websiteUrl}sitemap.xml`)
    expect(sitemap).toContain(`<loc>${websiteUrl}</loc>`)
    expect(llms).toContain(`Website: ${websiteUrl}`)
  })
})
