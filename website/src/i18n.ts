export const languages = ['ko', 'en', 'ja', 'zh-Hans'] as const

export type Language = (typeof languages)[number]

type InstallStep = {
  title: string
  description: string
}

type Copy = {
  pageTitle: string
  metaDescription: string
  skipLink: string
  navLabel: string
  brandHomeLabel: string
  githubLabel: string
  featuresLink: string
  downloadLink: string
  languageLabel: string
  hero: {
    eyebrow: string
    title: string
    accent: string
    lead: string
    download: string
    source: string
  }
  product: {
    label: string
    toolbarLabel: string
    record: string
    selectedArea: string
    fullScreen: string
    window: string
    file: string
    edit: string
    view: string
    date: string
  }
  trust: {
    label: string
    codec: string
    frameRate: string
    resolution: string
    free: string
  }
  features: {
    title: string
    accent: string
    frameRateTitle: string
    frameRateDescription: string
    matchedRate: string
    codecTitle: string
    codecDescription: string
    resolutionTitle: string
    resolutionDescription: string
  }
  free: {
    title: string
    accent: string
    description: string
    priceValue: string
    price: string
    duration: string
    watermark: string
  }
  download: {
    title: string
    accent: string
    lead: string
    appDescription: string
    releaseDescription: string
    button: string
    requirements: string
    installTitle: string
    installIntro: string
    steps: InstallStep[]
    detailsTitle: string
    detailsDescription: string
    sourceBefore: string
    sourceLink: string
    sourceAfter: string
  }
}

export const languageLabels: Record<Language, string> = {
  ko: 'KO',
  en: 'EN',
  ja: '日本語',
  'zh-Hans': '中文',
}

export const translations: Record<Language, Copy> = {
  ko: {
    pageTitle: 'Rokuga — 모든 프레임을, 그대로',
    metaDescription: 'Rokuga — 모든 프레임을 그대로 담는 무료 macOS 화면 녹화 앱',
    skipLink: '본문으로 이동',
    navLabel: '주요 메뉴',
    brandHomeLabel: 'Rokuga 홈',
    githubLabel: 'Rokuga GitHub 저장소',
    featuresLink: '기능',
    downloadLink: '다운로드',
    languageLabel: '언어 선택',
    hero: {
      eyebrow: 'Rokuga for Mac',
      title: '모든 프레임을,',
      accent: '그대로',
      lead: 'H.265 · 최대 5K · 화면 주사율 그대로',
      download: 'macOS용 다운로드',
      source: '소스 코드 보기',
    },
    product: {
      label: 'Rokuga의 실제 영역 선택 화면과 녹화 toolbar',
      toolbarLabel: '녹화 모드 선택',
      record: '녹화',
      selectedArea: '선택 영역',
      fullScreen: '전체 화면',
      window: '창',
      file: '파일',
      edit: '편집',
      view: '보기',
      date: '8월 19일 수요일  20:24',
    },
    trust: {
      label: 'Rokuga 핵심 가치',
      codec: '고효율 영상 코덱',
      frameRate: '모니터 주사율에 맞춰',
      resolution: '최대 해상도',
      free: '시간 제한도 워터마크도 없이',
    },
    features: {
      title: '60 fps를 넘어',
      accent: '화면과 같은 속도로',
      frameRateTitle: '움직임까지 매끄럽게',
      frameRateDescription: '디스플레이에 맞춘 프레임 레이트',
      matchedRate: 'fps · 144 Hz에 맞춤',
      codecTitle: '더 선명하게, 더 가볍게',
      codecDescription: 'H.264 또는 H.265',
      resolutionTitle: '픽셀 하나까지',
      resolutionDescription: 'Retina의 디테일을 최대 5K로',
    },
    free: {
      title: '무료',
      accent: '조건 없이',
      description: '시간 제한도, 워터마크도 없습니다.',
      priceValue: '₩0',
      price: '완전 무료',
      duration: '녹화 시간',
      watermark: '워터마크',
    },
    download: {
      title: 'Mac에서',
      accent: '바로',
      lead: '다운로드하고 녹화를 시작하세요.',
      appDescription: 'macOS 네이티브 화면 녹화 앱',
      releaseDescription: 'Apple Silicon과 Intel Mac을 지원하는 Universal 빌드입니다.',
      button: '출시 예정',
      requirements: 'macOS 15 Sequoia 이상 · Universal · 무료',
      installTitle: '처음 설치하시나요?',
      installIntro: '현재 프리뷰는 Apple 공증 전 빌드이므로 최초 실행 때 한 번의 확인이 필요합니다.',
      steps: [
        { title: 'DMG를 열고 앱을 복사', description: 'Rokuga를 응용 프로그램 폴더로 옮깁니다.' },
        { title: 'Rokuga를 한 번 실행', description: '확인되지 않은 개발자 안내가 나타날 수 있습니다.' },
        { title: '개인정보 보호 및 보안 열기', description: '시스템 설정에서 ‘그래도 열기’를 선택합니다.' },
      ],
      detailsTitle: '왜 이런 확인이 필요한가요?',
      detailsDescription: 'Rokuga는 아직 Apple Developer ID로 공증되지 않은 오픈소스 프리뷰이며, 소스와 빌드 과정은 GitHub에서 직접 확인할 수 있습니다.',
      sourceBefore: '직접 확인하고 빌드하고 싶다면 ',
      sourceLink: '소스 빌드 안내',
      sourceAfter: '를 이용하세요.',
    },
  },
  en: {
    pageTitle: 'Rokuga — Every frame, just as it is',
    metaDescription: 'Rokuga is a free native screen recorder for macOS with H.265, up to 5K, and frame rates matched to your display.',
    skipLink: 'Skip to content',
    navLabel: 'Main navigation',
    brandHomeLabel: 'Rokuga home',
    githubLabel: 'Rokuga repository on GitHub',
    featuresLink: 'Features',
    downloadLink: 'Download',
    languageLabel: 'Choose language',
    hero: {
      eyebrow: 'Rokuga for Mac',
      title: 'Every frame,',
      accent: 'just as it is',
      lead: 'H.265 · Up to 5K · Recording matched to your display',
      download: 'Download for macOS',
      source: 'View source code',
    },
    product: {
      label: 'Rokuga area selection screen and recording toolbar',
      toolbarLabel: 'Choose a recording mode',
      record: 'Record',
      selectedArea: 'Selected Area',
      fullScreen: 'Full Screen',
      window: 'Window',
      file: 'File',
      edit: 'Edit',
      view: 'View',
      date: 'Wed Aug 19  8:24 PM',
    },
    trust: {
      label: 'Rokuga highlights',
      codec: 'High-efficiency video codec',
      frameRate: 'Matched to your display',
      resolution: 'Maximum resolution',
      free: 'No time limits or watermarks',
    },
    features: {
      title: 'Beyond 60 fps',
      accent: 'At the speed of your display',
      frameRateTitle: 'Smooth in every frame',
      frameRateDescription: 'Frame rate matched to your display',
      matchedRate: 'fps · Matched to 144 Hz',
      codecTitle: 'Sharper. Lighter.',
      codecDescription: 'H.264 or H.265',
      resolutionTitle: 'Every last pixel',
      resolutionDescription: 'Retina detail, up to 5K',
    },
    free: {
      title: 'Free',
      accent: 'No strings attached',
      description: 'No time limits. No watermarks.',
      priceValue: '$0',
      price: 'Completely free',
      duration: 'Recording time',
      watermark: 'Watermarks',
    },
    download: {
      title: 'Ready',
      accent: 'for your Mac',
      lead: 'Download and start recording.',
      appDescription: 'Native screen recorder for macOS',
      releaseDescription: 'A Universal build for Apple Silicon and Intel Mac.',
      button: 'Coming soon',
      requirements: 'macOS 15 Sequoia or later · Universal · Free',
      installTitle: 'Installing for the first time?',
      installIntro: 'This preview has not yet been notarized by Apple, so one confirmation is required the first time you open it.',
      steps: [
        { title: 'Open the DMG and copy the app', description: 'Move Rokuga to your Applications folder.' },
        { title: 'Open Rokuga once', description: 'You may see an unidentified developer message.' },
        { title: 'Open Privacy & Security', description: 'In System Settings, select “Open Anyway.”' },
      ],
      detailsTitle: 'Why is this confirmation needed?',
      detailsDescription: 'Rokuga is an open-source preview that has not yet been notarized with an Apple Developer ID. You can inspect the source and build process on GitHub.',
      sourceBefore: 'Want to inspect and build it yourself? See the ',
      sourceLink: 'build from source guide',
      sourceAfter: '.',
    },
  },
  ja: {
    pageTitle: 'Rokuga — すべてのフレームを、そのまま',
    metaDescription: 'Rokugaは、H.265、最大5K、ディスプレイに合わせたフレームレートに対応する無料のmacOS画面録画アプリです。',
    skipLink: 'コンテンツへ移動',
    navLabel: 'メインメニュー',
    brandHomeLabel: 'Rokuga ホーム',
    githubLabel: 'RokugaのGitHubリポジトリ',
    featuresLink: '機能',
    downloadLink: 'ダウンロード',
    languageLabel: '言語を選択',
    hero: {
      eyebrow: 'Rokuga for Mac',
      title: 'すべてのフレームを、',
      accent: 'そのまま',
      lead: 'H.265 · 最大5K · ディスプレイに合わせた録画',
      download: 'macOS用をダウンロード',
      source: 'ソースコードを見る',
    },
    product: {
      label: 'Rokugaの範囲選択画面と録画toolbar',
      toolbarLabel: '録画モードを選択',
      record: '録画',
      selectedArea: '選択範囲',
      fullScreen: 'フルスクリーン',
      window: 'ウインドウ',
      file: 'ファイル',
      edit: '編集',
      view: '表示',
      date: '8月19日 水曜日  20:24',
    },
    trust: {
      label: 'Rokugaの特長',
      codec: '高効率ビデオコーデック',
      frameRate: 'ディスプレイに合わせて',
      resolution: '最大解像度',
      free: '時間制限もウォーターマークもなし',
    },
    features: {
      title: '60 fpsを超えて',
      accent: '画面と同じ速さで',
      frameRateTitle: '動きまで、なめらかに',
      frameRateDescription: 'ディスプレイに合わせたフレームレート',
      matchedRate: 'fps · 144 Hzに合わせて',
      codecTitle: 'より鮮明に、より軽く',
      codecDescription: 'H.264またはH.265',
      resolutionTitle: '1ピクセルまで鮮明に',
      resolutionDescription: 'Retinaのディテールを最大5Kで',
    },
    free: {
      title: '無料',
      accent: '条件なし',
      description: '時間制限も、ウォーターマークもありません。',
      priceValue: '¥0',
      price: '完全無料',
      duration: '録画時間',
      watermark: 'ウォーターマーク',
    },
    download: {
      title: 'Macですぐに',
      accent: '始めよう',
      lead: 'ダウンロードして、録画を始めましょう。',
      appDescription: 'macOSネイティブの画面録画アプリ',
      releaseDescription: 'Apple SiliconとIntel Macに対応したUniversalビルドです。',
      button: '近日公開',
      requirements: 'macOS 15 Sequoia以降 · Universal · 無料',
      installTitle: '初めてインストールしますか？',
      installIntro: '現在のプレビュー版はAppleによる公証前のため、初回起動時に一度だけ確認が必要です。',
      steps: [
        { title: 'DMGを開いてアプリをコピー', description: 'Rokugaをアプリケーションフォルダに移動します。' },
        { title: 'Rokugaを一度起動', description: '未確認の開発元についての案内が表示されることがあります。' },
        { title: '「プライバシーとセキュリティ」を開く', description: 'システム設定で「このまま開く」を選択します。' },
      ],
      detailsTitle: 'なぜこの確認が必要ですか？',
      detailsDescription: 'Rokugaは、まだApple Developer IDで公証されていないオープンソースのプレビュー版です。ソースとビルド手順はGitHubで確認できます。',
      sourceBefore: '自分で確認してビルドする場合は、',
      sourceLink: 'ソースからのビルド手順',
      sourceAfter: 'をご覧ください。',
    },
  },
  'zh-Hans': {
    pageTitle: 'Rokuga — 每一帧，原样呈现',
    metaDescription: 'Rokuga 是一款免费的 macOS 屏幕录制应用，支持 H.265、最高 5K 和匹配显示器的录制帧率。',
    skipLink: '跳到正文',
    navLabel: '主菜单',
    brandHomeLabel: 'Rokuga 首页',
    githubLabel: 'Rokuga GitHub 仓库',
    featuresLink: '功能',
    downloadLink: '下载',
    languageLabel: '选择语言',
    hero: {
      eyebrow: 'Rokuga for Mac',
      title: '每一帧，',
      accent: '原样呈现',
      lead: 'H.265 · 最高 5K · 匹配显示器刷新率录制',
      download: '下载 macOS 版',
      source: '查看源代码',
    },
    product: {
      label: 'Rokuga 区域选择界面和录制工具栏',
      toolbarLabel: '选择录制模式',
      record: '录制',
      selectedArea: '所选区域',
      fullScreen: '全屏',
      window: '窗口',
      file: '文件',
      edit: '编辑',
      view: '显示',
      date: '8月19日 周三  20:24',
    },
    trust: {
      label: 'Rokuga 核心亮点',
      codec: '高效视频编码',
      frameRate: '匹配显示器刷新率',
      resolution: '最高分辨率',
      free: '无时长限制，无水印',
    },
    features: {
      title: '超越 60 fps',
      accent: '与屏幕同速',
      frameRateTitle: '每一帧，都流畅',
      frameRateDescription: '匹配显示器的录制帧率',
      matchedRate: 'fps · 匹配 144 Hz',
      codecTitle: '更清晰，更轻巧',
      codecDescription: 'H.264 或 H.265',
      resolutionTitle: '每个像素都清晰',
      resolutionDescription: '最高以 5K 呈现 Retina 细节',
    },
    free: {
      title: '免费',
      accent: '没有附加条件',
      description: '没有时长限制，也没有水印。',
      priceValue: '¥0',
      price: '完全免费',
      duration: '录制时长',
      watermark: '水印',
    },
    download: {
      title: '在 Mac 上',
      accent: '即刻开始',
      lead: '下载即可开始录制。',
      appDescription: 'macOS 原生屏幕录制应用',
      releaseDescription: '支持 Apple Silicon 和 Intel Mac 的 Universal 版本。',
      button: '即将推出',
      requirements: 'macOS 15 Sequoia 或更高版本 · Universal · 免费',
      installTitle: '第一次安装？',
      installIntro: '当前预览版尚未经过 Apple 公证，首次启动时需要确认一次。',
      steps: [
        { title: '打开 DMG 并复制应用', description: '将 Rokuga 移到“应用程序”文件夹。' },
        { title: '启动一次 Rokuga', description: '系统可能会显示无法验证开发者的提示。' },
        { title: '打开“隐私与安全性”', description: '在“系统设置”中选择“仍要打开”。' },
      ],
      detailsTitle: '为什么需要确认？',
      detailsDescription: 'Rokuga 是尚未通过 Apple Developer ID 公证的开源预览版。你可以在 GitHub 上查看源代码和构建过程。',
      sourceBefore: '想自行检查并构建？请查看',
      sourceLink: '从源代码构建指南',
      sourceAfter: '。',
    },
  },
}

export function isLanguage(value: string | null): value is Language {
  return languages.some((language) => language === value)
}

function matchLocale(locale: string): Language | undefined {
  const normalized = locale.toLowerCase().replaceAll('_', '-')

  if (normalized === 'ko' || normalized.startsWith('ko-')) return 'ko'
  if (normalized === 'en' || normalized.startsWith('en-')) return 'en'
  if (normalized === 'ja' || normalized.startsWith('ja-')) return 'ja'
  if (
    normalized === 'zh-cn' || normalized.startsWith('zh-cn-') ||
    normalized === 'zh-sg' || normalized.startsWith('zh-sg-') ||
    normalized === 'zh-hans' || normalized.startsWith('zh-hans-')
  ) return 'zh-Hans'

  return undefined
}

export function matchLanguage(locales: readonly string[]): Language {
  for (const locale of locales) {
    const language = matchLocale(locale)
    if (language) return language
  }

  return 'en'
}

export function selectLanguage(savedLanguage: string | null, locales: readonly string[]): Language {
  return isLanguage(savedLanguage) ? savedLanguage : matchLanguage(locales)
}
