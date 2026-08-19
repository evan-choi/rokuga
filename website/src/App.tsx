import logoUrl from '../../docs/logo.png'
import toolbarUrl from '../../design/mockups/assets/rokuga-recording-toolbar.png'

export default function App() {
  return (
    <>
      <a className="skip-link" href="#main">본문으로 이동</a>

      <header className="site-header">
        <nav className="nav container" aria-label="주요 메뉴">
          <a className="brand" href="#top" aria-label="Rokuga 홈">
            <img src={logoUrl} alt="" />
            <span>Rokuga</span>
          </a>
          <div className="nav-links">
            <a href="#features">기능</a>
            <a className="github-link" href="https://github.com/evan-choi/rokuga" aria-label="Rokuga GitHub 저장소">
              <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 2C6.477 2 2 6.59 2 12.253c0 4.53 2.865 8.373 6.839 9.729.5.095.682-.222.682-.493 0-.244-.009-.89-.014-1.747-2.782.619-3.369-1.374-3.369-1.374-.455-1.183-1.11-1.497-1.11-1.497-.908-.636.069-.623.069-.623 1.003.072 1.531 1.056 1.531 1.056.892 1.566 2.341 1.114 2.91.852.091-.662.349-1.114.635-1.37-2.221-.259-4.556-1.14-4.556-5.07 0-1.12.389-2.036 1.029-2.754-.103-.26-.446-1.303.098-2.715 0 0 .84-.275 2.75 1.052A9.356 9.356 0 0 1 12 6.954a9.36 9.36 0 0 1 2.504.346c1.909-1.327 2.747-1.052 2.747-1.052.546 1.412.203 2.455.1 2.715.64.718 1.027 1.634 1.027 2.754 0 3.94-2.339 4.808-4.566 5.061.359.317.679.943.679 1.9 0 1.372-.013 2.479-.013 2.815 0 .274.18.593.688.492C19.138 20.624 22 16.783 22 12.253 22 6.59 17.523 2 12 2Z"/></svg>
              <span>GitHub</span>
            </a>
            <a className="nav-download" href="#download">다운로드</a>
          </div>
        </nav>
      </header>

      <main id="main">
        <section className="hero" id="top">
          <div className="container">
            <div className="hero-copy">
              <div className="eyebrow">Rokuga for Mac</div>
              <h1>모든 프레임을,<br /><span className="accent">그대로</span></h1>
              <p className="hero-lead">H.265 · 최대 5K · 모니터 주사율에 맞춘 녹화</p>
              <div className="hero-actions">
                <a className="button button-primary" href="#download">
                  macOS용 다운로드
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M12 3v12"/><path d="m7 10 5 5 5-5"/><path d="M5 21h14"/></svg>
                </a>
                <a className="button button-secondary" href="https://github.com/evan-choi/rokuga">
                  소스 코드 보기
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="m9 18 6-6-6-6"/></svg>
                </a>
              </div>
            </div>

            <div className="product-shell" role="img" aria-label="Rokuga의 실제 영역 선택 화면과 녹화 toolbar">
              <div className="product-stage">
                <div className="mac-menu" aria-hidden="true">
                  <span className="apple-logo"></span>
                  <strong>Finder</strong><span>파일</span><span>편집</span><span>보기</span>
                  <span className="grow"></span><span>8월 19일 수요일&nbsp;&nbsp;20:24</span>
                </div>
                <div className="selection" aria-hidden="true">
                  <span className="dimension-label">960 × 540</span>
                  <i className="handle" /><i className="handle" /><i className="handle" /><i className="handle" />
                  <i className="handle" /><i className="handle" /><i className="handle" /><i className="handle" />
                </div>
                <img className="actual-toolbar" src={toolbarUrl} alt="" />
              </div>
            </div>
          </div>
        </section>

        <div className="trust-strip container" aria-label="Rokuga 핵심 가치">
          <div className="trust-item"><strong>H.265</strong><span>고효율 영상 코덱</span></div>
          <div className="trust-item"><strong>60 fps+</strong><span>모니터 주사율에 맞춰</span></div>
          <div className="trust-item"><strong>5K</strong><span>최대 해상도</span></div>
          <div className="trust-item"><strong>무료</strong><span>시간 제한도 워터마크도 없이</span></div>
        </div>

        <section className="section" id="features">
          <div className="container">
            <div className="section-heading">
              <p className="section-kicker">Capture</p>
              <h2>60 fps를 넘어<br />화면과 같은 속도로</h2>
            </div>

            <div className="bento">
              <article className="feature-card feature-card-wide">
                <h3>주사율에 맞춘 프레임 레이트</h3>
                <p>모니터를 감지해 녹화 fps를 맞춥니다.</p>
                <div className="rate-visual" aria-hidden="true">
                  <div className="rate-tile"><strong>30</strong><span>fps</span></div>
                  <div className="rate-tile"><strong>60</strong><span>fps</span></div>
                  <div className="rate-tile active"><strong>144</strong><span>fps · 144 Hz에 맞춤</span></div>
                </div>
              </article>

              <article className="feature-card">
                <h3>더 선명하게, 더 가볍게</h3>
                <p>H.264 또는 H.265</p>
                <div className="codec-visual" aria-hidden="true">
                  <div className="codec-option"><strong>H.264</strong><span>AVC · MP4 / MOV</span></div>
                  <div className="codec-option active"><strong>H.265</strong><span>HEVC · MP4 / MOV</span></div>
                </div>
              </article>

              <article className="feature-card">
                <h3>픽셀 하나까지</h3>
                <p>Retina의 디테일을 최대 5K로</p>
                <div className="resolution-visual" aria-hidden="true">
                  <strong>5K</strong>
                  <span>up to 5120 × 2880</span>
                </div>
              </article>
            </div>
          </div>
        </section>

        <section className="section free-section">
          <div className="container">
            <div className="free-panel">
              <div className="free-copy">
                <p className="section-kicker">Free</p>
                <h2>무료<br />조건 없이</h2>
                <p>시간 제한도, 워터마크도 없습니다.</p>
                <ul className="free-list">
                  <li><strong>₩0</strong><span>완전 무료</span></li>
                  <li><strong>∞</strong><span>녹화 시간</span></li>
                  <li><strong>0</strong><span>워터마크</span></li>
                </ul>
              </div>
            </div>
          </div>
        </section>

        <section className="section download-section" id="download">
          <div className="container">
            <div className="section-heading">
              <p className="section-kicker">Download</p>
              <h2>Mac에서<br />바로</h2>
              <p className="section-lead">다운로드하고 녹화를 시작하세요.</p>
            </div>

            <div className="download-grid">
              <article className="download-main">
                <div className="app-lockup">
                  <div className="app-icon"><img src={logoUrl} alt="" /></div>
                  <div><h3>Rokuga</h3><p>Native screen recorder for macOS</p></div>
                </div>
                <div className="release-copy">
                  <h2>Rokuga 0.1.0 Preview</h2>
                  <p>Apple Silicon과 Intel Mac을 지원하는 Universal 빌드입니다.</p>
                </div>
                <a className="button button-primary download-button" href="https://github.com/evan-choi/rokuga/releases/latest">
                  DMG 다운로드
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M12 3v12"/><path d="m7 10 5 5 5-5"/><path d="M5 21h14"/></svg>
                </a>
                <p className="release-meta">macOS 13.3 Ventura 이상 · Universal · 무료</p>
              </article>

              <aside className="install-card" aria-labelledby="install-title">
                <h3 id="install-title">처음 설치하시나요?</h3>
                <p className="install-intro">현재 프리뷰는 Apple 공증 전 빌드이므로 최초 실행 때 한 번의 확인이 필요합니다.</p>
                <ol className="steps">
                  <li><strong>DMG를 열고 앱을 복사</strong><span>Rokuga를 응용 프로그램 폴더로 옮깁니다.</span></li>
                  <li><strong>Rokuga를 한 번 실행</strong><span>확인되지 않은 개발자 안내가 나타날 수 있습니다.</span></li>
                  <li><strong>개인정보 보호 및 보안 열기</strong><span>시스템 설정에서 ‘그래도 열기’를 선택합니다.</span></li>
                </ol>
                <details>
                  <summary>왜 이런 확인이 필요한가요?</summary>
                  <p>Rokuga는 아직 Apple Developer ID로 공증되지 않은 오픈소스 프리뷰이며, 소스와 빌드 과정은 GitHub에서 직접 확인할 수 있습니다.</p>
                </details>
                <div className="source-note">직접 확인하고 빌드하고 싶다면 <a href="https://github.com/evan-choi/rokuga#build-from-source">소스 빌드 안내</a>를 이용하세요.</div>
              </aside>
            </div>
          </div>
        </section>
      </main>

      <footer>
        <div className="footer-content container">
          <a className="brand" href="#top"><img src={logoUrl} alt="" /><span>Rokuga</span></a>
          <span>© 2026 Rokuga contributors</span>
          <a href="https://github.com/evan-choi/rokuga">GitHub</a>
          <a href="https://github.com/evan-choi/rokuga/blob/main/LICENSE">MIT License</a>
        </div>
      </footer>

    </>
  )
}
