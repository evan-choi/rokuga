import { useEffect, useRef, useState, type KeyboardEvent, type PointerEvent } from 'react'
import logoUrl from '../../docs/logo.png'
import { isLanguage, languageLabels, languages, selectLanguage, translations } from './i18n'
import { initialSelection, mobileInitialSelection, moveSelection, resizeSelection, type SelectionHandle, type SelectionRegion } from './selection'

const LANGUAGE_STORAGE_KEY = 'rokuga-language'
type CaptureMode = 'selectedArea' | 'fullScreen' | 'window'
type SelectionDrag = {
  pointerId: number
  startX: number
  startY: number
  region: SelectionRegion
  handle: SelectionHandle | null
}

export default function App() {
  const [language, setLanguage] = useState(() => selectLanguage(
    localStorage.getItem(LANGUAGE_STORAGE_KEY),
    navigator.languages,
  ))
  const [captureMode, setCaptureMode] = useState<CaptureMode>('selectedArea')
  const [selectionBaseline] = useState(() => (
    window.matchMedia('(max-width: 660px)').matches ? mobileInitialSelection : initialSelection
  ))
  const [selection, setSelection] = useState(selectionBaseline)
  const [selectionDrag, setSelectionDrag] = useState<SelectionHandle | 'move' | null>(null)
  const productStageRef = useRef<HTMLDivElement>(null)
  const selectionDragRef = useRef<SelectionDrag | null>(null)
  const copy = translations[language]

  useEffect(() => {
    const localizedCopy = translations[language]
    const description = document.querySelector<HTMLMetaElement>('meta[name="description"]')

    document.documentElement.lang = language
    document.title = localizedCopy.pageTitle
    description?.setAttribute('content', localizedCopy.metaDescription)
    localStorage.setItem(LANGUAGE_STORAGE_KEY, language)
  }, [language])

  const startSelectionDrag = (event: PointerEvent<HTMLDivElement>) => {
    if (event.button !== 0) return

    const handle = (event.target as HTMLElement).closest<HTMLElement>('[data-handle]')
      ?.dataset.handle as SelectionHandle | undefined
    selectionDragRef.current = {
      pointerId: event.pointerId,
      startX: event.clientX,
      startY: event.clientY,
      region: selection,
      handle: handle ?? null,
    }
    setSelectionDrag(handle ?? 'move')
    productStageRef.current?.setPointerCapture(event.pointerId)
    event.preventDefault()
  }

  const updateSelectionDrag = (event: PointerEvent<HTMLDivElement>) => {
    const drag = selectionDragRef.current
    const stage = productStageRef.current?.getBoundingClientRect()
    if (!drag || drag.pointerId !== event.pointerId || !stage) return

    const dx = (event.clientX - drag.startX) / stage.width
    const dy = (event.clientY - drag.startY) / stage.height
    setSelection(drag.handle
      ? resizeSelection(drag.region, drag.handle, dx, dy, 50 / stage.width, 50 / stage.height)
      : moveSelection(drag.region, dx, dy))
  }

  const endSelectionDrag = (event: PointerEvent<HTMLDivElement>) => {
    if (selectionDragRef.current?.pointerId !== event.pointerId) return
    selectionDragRef.current = null
    setSelectionDrag(null)
    if (event.currentTarget.hasPointerCapture(event.pointerId)) {
      event.currentTarget.releasePointerCapture(event.pointerId)
    }
  }

  const moveSelectionWithKeyboard = (event: KeyboardEvent<HTMLDivElement>) => {
    const step = event.shiftKey ? 0.05 : 0.01
    let dx = 0
    let dy = 0

    if (event.key === 'ArrowLeft') dx = -step
    else if (event.key === 'ArrowRight') dx = step
    else if (event.key === 'ArrowUp') dy = -step
    else if (event.key === 'ArrowDown') dy = step
    else return

    setSelection((region) => moveSelection(region, dx, dy))
    event.preventDefault()
  }

  return (
    <>
      <a className="skip-link" href="#main">{copy.skipLink}</a>

      <header className="site-header">
        <nav className="nav container" aria-label={copy.navLabel}>
          <a className="brand" href="#top" aria-label={copy.brandHomeLabel}>
            <img src={logoUrl} alt="" />
            <span>Rokuga</span>
          </a>
          <div className="nav-links">
            <a href="#features">{copy.featuresLink}</a>
            <a className="github-link" href="https://github.com/evan-choi/rokuga" aria-label={copy.githubLabel}>
              <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 2C6.477 2 2 6.59 2 12.253c0 4.53 2.865 8.373 6.839 9.729.5.095.682-.222.682-.493 0-.244-.009-.89-.014-1.747-2.782.619-3.369-1.374-3.369-1.374-.455-1.183-1.11-1.497-1.11-1.497-.908-.636.069-.623.069-.623 1.003.072 1.531 1.056 1.531 1.056.892 1.566 2.341 1.114 2.91.852.091-.662.349-1.114.635-1.37-2.221-.259-4.556-1.14-4.556-5.07 0-1.12.389-2.036 1.029-2.754-.103-.26-.446-1.303.098-2.715 0 0 .84-.275 2.75 1.052A9.356 9.356 0 0 1 12 6.954a9.36 9.36 0 0 1 2.504.346c1.909-1.327 2.747-1.052 2.747-1.052.546 1.412.203 2.455.1 2.715.64.718 1.027 1.634 1.027 2.754 0 3.94-2.339 4.808-4.566 5.061.359.317.679.943.679 1.9 0 1.372-.013 2.479-.013 2.815 0 .274.18.593.688.492C19.138 20.624 22 16.783 22 12.253 22 6.59 17.523 2 12 2Z"/></svg>
              <span>GitHub</span>
            </a>
            <label className="language-picker">
              <span className="visually-hidden">{copy.languageLabel}</span>
              <select
                className="language-select"
                value={language}
                aria-label={copy.languageLabel}
                onChange={(event) => {
                  if (isLanguage(event.target.value)) setLanguage(event.target.value)
                }}
              >
                {languages.map((option) => (
                  <option key={option} value={option} lang={option}>{languageLabels[option]}</option>
                ))}
              </select>
            </label>
            <a className="nav-download" href="#download">{copy.downloadLink}</a>
          </div>
        </nav>
      </header>

      <main id="main">
        <section className="hero" id="top">
          <div className="container">
            <div className="hero-copy">
              <div className="eyebrow">{copy.hero.eyebrow}</div>
              <h1>{copy.hero.title}<br /><span className="accent">{copy.hero.accent}</span></h1>
              <p className="hero-lead">{copy.hero.lead}</p>
              <div className="hero-actions">
                <a className="button button-primary" href="#download">
                  {copy.hero.download}
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M12 3v12"/><path d="m7 10 5 5 5-5"/><path d="M5 21h14"/></svg>
                </a>
                <a className="button button-secondary" href="https://github.com/evan-choi/rokuga">
                  {copy.hero.source}
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="m9 18 6-6-6-6"/></svg>
                </a>
              </div>
            </div>

            <div className="product-shell" role="group" aria-label={copy.product.label}>
              <div
                className="product-stage"
                ref={productStageRef}
                data-mode={captureMode}
                onPointerMove={updateSelectionDrag}
                onPointerUp={endSelectionDrag}
                onPointerCancel={endSelectionDrag}
              >
                <div className="mac-menu" aria-hidden="true">
                  <span className="apple-logo"></span>
                  <strong>Finder</strong><span>{copy.product.file}</span><span>{copy.product.edit}</span><span>{copy.product.view}</span>
                  <span className="grow"></span><span>{copy.product.date}</span>
                </div>
                <div className="full-screen-target" aria-hidden="true" />
                <div className="window-target" aria-hidden="true">
                  <div className="window-target-bar"><i /><i /><i /></div>
                  <div className="window-target-body"><span /><span /><span /></div>
                </div>
                <div
                  className="selection"
                  role="group"
                  tabIndex={captureMode === 'selectedArea' ? 0 : -1}
                  aria-label={copy.product.selectedArea}
                  aria-hidden={captureMode !== 'selectedArea'}
                  data-dragging={selectionDrag ?? undefined}
                  style={{
                    top: `${selection.y * 100}%`,
                    left: `${selection.x * 100}%`,
                    width: `${selection.width * 100}%`,
                    height: `${selection.height * 100}%`,
                  }}
                  onKeyDown={moveSelectionWithKeyboard}
                  onPointerDown={startSelectionDrag}
                >
                  <span className="dimension-label">
                    {Math.round(960 * selection.width / selectionBaseline.width)} × {Math.round(540 * selection.height / selectionBaseline.height)}
                  </span>
                  <i className="handle" data-handle="topLeft" aria-hidden="true" />
                  <i className="handle" data-handle="top" aria-hidden="true" />
                  <i className="handle" data-handle="topRight" aria-hidden="true" />
                  <i className="handle" data-handle="right" aria-hidden="true" />
                  <i className="handle" data-handle="bottomRight" aria-hidden="true" />
                  <i className="handle" data-handle="bottom" aria-hidden="true" />
                  <i className="handle" data-handle="bottomLeft" aria-hidden="true" />
                  <i className="handle" data-handle="left" aria-hidden="true" />
                </div>
                <div className="actual-toolbar" role="toolbar" aria-label={copy.product.toolbarLabel}>
                  <span className="toolbar-close">
                    <svg viewBox="0 0 20 20" aria-hidden="true"><circle cx="10" cy="10" r="9.5" /><path d="m7 7 6 6m0-6-6 6" /></svg>
                  </span>
                  <div className="toolbar-modes">
                    <button
                      className="toolbar-mode"
                      type="button"
                      aria-label={copy.product.selectedArea}
                      aria-pressed={captureMode === 'selectedArea'}
                      data-tooltip={copy.product.selectedArea}
                      onClick={() => setCaptureMode('selectedArea')}
                    >
                      <span className="toolbar-symbol selected-area-symbol" aria-hidden="true" />
                    </button>
                    <button
                      className="toolbar-mode"
                      type="button"
                      aria-label={copy.product.fullScreen}
                      aria-pressed={captureMode === 'fullScreen'}
                      data-tooltip={copy.product.fullScreen}
                      onClick={() => setCaptureMode('fullScreen')}
                    >
                      <span className="toolbar-symbol full-screen-symbol" aria-hidden="true" />
                    </button>
                    <button
                      className="toolbar-mode"
                      type="button"
                      aria-label={copy.product.window}
                      aria-pressed={captureMode === 'window'}
                      data-tooltip={copy.product.window}
                      onClick={() => setCaptureMode('window')}
                    >
                      <span className="toolbar-symbol window-symbol" aria-hidden="true" />
                    </button>
                  </div>
                  <span className="toolbar-drag" />
                  <span className="toolbar-options">
                    <svg viewBox="0 0 20 20" aria-hidden="true"><path d="M4 6h12M4 10h12M4 14h12" /><circle cx="8" cy="6" r="1.35" /><circle cx="13" cy="10" r="1.35" /><circle cx="7" cy="14" r="1.35" /></svg>
                  </span>
                  <span className="toolbar-record">{copy.product.record}</span>
                </div>
                <span className="mode-status" aria-live="polite">{copy.product[captureMode]}</span>
              </div>
              <div className="product-demo-meta">
                <strong>{copy.product.demoLabel}</strong>
                <span>{copy.product.hint}</span>
              </div>
            </div>
          </div>
        </section>

        <section className="highlights">
          <div className="container">
            <div className="section-heading highlights-heading">
              <p className="section-kicker">{copy.trust.kicker}</p>
              <h2>{copy.trust.title}</h2>
            </div>
            <div className="trust-strip" aria-label={copy.trust.label}>
              <div className="trust-item"><strong>H.265</strong><span>{copy.trust.codec}</span></div>
              <div className="trust-item"><strong>60 fps+</strong><span>{copy.trust.frameRate}</span></div>
              <div className="trust-item"><strong>5K</strong><span>{copy.trust.resolution}</span></div>
              <div className="trust-item"><strong>{copy.free.title}</strong><span>{copy.trust.free}</span></div>
            </div>
          </div>
        </section>

        <section className="section features-section" id="features">
          <div className="container">
            <div className="section-heading">
              <p className="section-kicker">{copy.features.kicker}</p>
              <h2>{copy.features.title}<br />{copy.features.accent}</h2>
            </div>

            <div className="bento">
              <article className="feature-card feature-card-wide feature-card-dark">
                <h3>{copy.features.frameRateTitle}</h3>
                <p>{copy.features.frameRateDescription}</p>
                <div className="rate-visual" aria-hidden="true">
                  <div className="rate-tile"><strong>30</strong><span>fps</span></div>
                  <div className="rate-tile"><strong>60</strong><span>fps</span></div>
                  <div className="rate-tile active"><strong>144</strong><span>{copy.features.matchedRate}</span></div>
                </div>
              </article>

              <article className="feature-card feature-card-codec">
                <h3>{copy.features.codecTitle}</h3>
                <p>{copy.features.codecDescription}</p>
                <div className="codec-visual" aria-hidden="true">
                  <div className="codec-option"><strong>H.264</strong><span>AVC · MP4 / MOV</span></div>
                  <div className="codec-option active"><strong>H.265</strong><span>HEVC · MP4 / MOV</span></div>
                </div>
              </article>

              <article className="feature-card feature-card-resolution">
                <h3>{copy.features.resolutionTitle}</h3>
                <p>{copy.features.resolutionDescription}</p>
                <div className="resolution-visual" aria-hidden="true">
                  <strong>5K</strong>
                  <span>{copy.features.resolutionLimit}</span>
                </div>
              </article>
            </div>
          </div>
        </section>

        <section className="section free-section">
          <div className="container">
            <div className="free-panel">
              <div className="free-copy">
                <p className="section-kicker">{copy.free.kicker}</p>
                <h2>{copy.free.title}<br />{copy.free.accent}</h2>
                <p>{copy.free.description}</p>
                <ul className="free-list">
                  <li><strong>{copy.free.priceValue}</strong><span>{copy.free.price}</span></li>
                  <li><strong>∞</strong><span>{copy.free.duration}</span></li>
                  <li><strong>0</strong><span>{copy.free.watermark}</span></li>
                </ul>
              </div>
            </div>
          </div>
        </section>

        <section className="section download-section" id="download">
          <div className="container">
            <div className="section-heading">
              <p className="section-kicker">{copy.download.kicker}</p>
              <h2>{copy.download.title}<br />{copy.download.accent}</h2>
              <p className="section-lead">{copy.download.lead}</p>
            </div>

            <div className="download-grid">
              <article className="download-main">
                <div className="app-lockup">
                  <div className="app-icon"><img src={logoUrl} alt="" /></div>
                  <div><h3>Rokuga</h3><p>{copy.download.appDescription}</p></div>
                </div>
                <div className="release-copy">
                  <h2>{copy.download.appStoreName}</h2>
                  <p>{copy.download.appStoreDescription}</p>
                </div>
                <button className="button button-disabled download-button" type="button" disabled>
                  {copy.download.appStoreButton}
                </button>
                <p className="release-meta">{copy.download.requirements}</p>
              </article>

              <article className="install-card brew-card">
                <div className="brew-lockup" aria-hidden="true"><span>&gt;_</span></div>
                <div className="release-copy">
                  <h2>{copy.download.brewName}</h2>
                  <p>{copy.download.brewDescription}</p>
                </div>
                <code className="brew-command">{copy.download.brewCommand}</code>
                <button className="button button-disabled download-button" type="button" disabled>
                  {copy.download.brewButton}
                </button>
                <div className="source-note">
                  {copy.download.sourceBefore}
                  <a href="https://github.com/evan-choi/rokuga#build-from-source">{copy.download.sourceLink}</a>
                  {copy.download.sourceAfter}
                </div>
              </article>
            </div>
          </div>
        </section>
      </main>

      <footer>
        <div className="footer-content container">
          <a className="brand" href="#top"><img src={logoUrl} alt="" /><span>Rokuga</span></a>
          <span>© 2026 Rokuga contributors</span>
          <a href="https://github.com/evan-choi/rokuga">GitHub</a>
          <a href="https://github.com/evan-choi/rokuga/blob/main/LICENSE">Apache License 2.0</a>
        </div>
      </footer>

    </>
  )
}
