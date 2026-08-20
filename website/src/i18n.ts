export const languages = ['ko', 'en', 'ja', 'zh-Hans'] as const

export type Language = (typeof languages)[number]

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
    options: string
    file: string
    edit: string
    view: string
    demoLabel: string
    hint: string
  }
  trust: {
    label: string
    kicker: string
    title: string
    codec: string
    frameRate: string
    resolution: string
    free: string
  }
  features: {
    kicker: string
    title: string
    accent: string
    frameRateTitle: string
    frameRateDescription: string
    matchedRate: string
    codecTitle: string
    codecDescription: string
    resolutionTitle: string
    resolutionDescription: string
    resolutionLimit: string
  }
  free: {
    kicker: string
    title: string
    accent: string
    description: string
    priceValue: string
    price: string
    duration: string
    watermark: string
  }
  download: {
    kicker: string
    title: string
    accent: string
    lead: string
    appDescription: string
    appStoreName: string
    appStoreDescription: string
    appStoreButton: string
    requirements: string
    brewName: string
    brewDescription: string
    brewCommand: string
    brewCopy: string
    brewCopied: string
    brewCopyFailed: string
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
    pageTitle: 'Rokuga — 화면의 움직임을, 있는 그대로',
    metaDescription: 'Rokuga는 디스플레이에 맞춘 프레임 레이트, H.265, 최대 5K를 지원하는 무료 오픈소스 macOS 화면 녹화 앱입니다.',
    skipLink: '본문으로 이동',
    navLabel: '주요 메뉴',
    brandHomeLabel: 'Rokuga 홈',
    githubLabel: 'Rokuga GitHub 저장소',
    featuresLink: '제품 살펴보기',
    downloadLink: '다운로드',
    languageLabel: '언어 선택',
    hero: {
      eyebrow: 'Rokuga for Mac',
      title: '화면의 움직임을,',
      accent: '있는 그대로.',
      lead: '디스플레이와 같은 속도로, Retina의 디테일까지. 무료 macOS 화면 녹화 앱.',
      download: '다운로드',
      source: 'GitHub에서 보기',
    },
    product: {
      label: 'Rokuga 영역 선택 화면 및 녹화 도구 막대 체험',
      toolbarLabel: '녹화 모드 선택',
      record: '녹화',
      selectedArea: '선택 영역',
      fullScreen: '전체 화면',
      window: '창',
      options: '옵션',
      file: '파일',
      edit: '편집',
      view: '보기',
      demoLabel: '직접 움직여 보세요',
      hint: '선택 영역을 드래그하거나 가장자리를 잡아 크기를 바꿀 수 있습니다.',
    },
    trust: {
      label: 'Rokuga 주요 기능',
      kicker: '한눈에 보기',
      title: '선명함, 속도, 자유까지.',
      codec: '선명한 화질, 더 효율적인 파일',
      frameRate: '디스플레이에 맞춘 프레임 레이트',
      resolution: 'Retina 디테일까지',
      free: '시간 제한도 워터마크도 없이',
    },
    features: {
      kicker: '녹화',
      title: '60 fps를 넘어.',
      accent: '화면과 같은 속도로.',
      frameRateTitle: '프레임 레이트. 움직임의 차이.',
      frameRateDescription: '30 fps와 60 fps는 물론, 디스플레이 주사율에 맞춰 빠른 움직임도 자연스럽게 기록합니다.',
      matchedRate: 'fps · 144 Hz와 일치',
      codecTitle: 'H.265. 선명함은 남기고, 용량은 덜고.',
      codecDescription: 'H.264와 H.265. MP4와 MOV. 원하는 조합으로.',
      resolutionTitle: '최대 5K. 작은 디테일까지 크게.',
      resolutionDescription: 'Retina 디스플레이의 픽셀을 최대 5120 × 2880 해상도로 담습니다.',
      resolutionLimit: '최대 5120 × 2880',
    },
    free: {
      kicker: '무료',
      title: '무료.',
      accent: '그 말 그대로.',
      description: '시간 제한도, 워터마크도 없습니다. 필요한 기능은 모두 열려 있습니다.',
      priceValue: '₩0',
      price: '앱 가격',
      duration: '시간 제한 없음',
      watermark: '워터마크 없음',
    },
    download: {
      kicker: '다운로드',
      title: '원하는 방식으로,',
      accent: '바로 시작하세요.',
      lead: 'Homebrew로 지금 설치하세요. Mac App Store 버전도 곧 출시됩니다.',
      appDescription: 'Mac을 위한 네이티브 화면 녹화 앱',
      appStoreName: 'Mac App Store',
      appStoreDescription: '클릭 한 번으로 설치하고, 업데이트도 자동으로.',
      appStoreButton: 'App Store 출시 예정',
      requirements: 'macOS 15 Sequoia 이상 · Universal · 무료',
      brewName: 'Homebrew',
      brewDescription: '터미널 한 줄로 설치하고, Homebrew로 간편하게 업데이트하세요.',
      brewCommand: 'brew install --cask evan-choi/tap/rokuga',
      brewCopy: '복사',
      brewCopied: '복사됨',
      brewCopyFailed: '복사 실패',
    },
  },
  en: {
    pageTitle: 'Rokuga — Your screen in motion, just as it happens',
    metaDescription: 'Rokuga is a free, open-source screen recorder for Mac that records at display-matched frame rates, with H.265 and resolutions up to 5K.',
    skipLink: 'Skip to content',
    navLabel: 'Main navigation',
    brandHomeLabel: 'Rokuga home',
    githubLabel: 'Rokuga repository on GitHub',
    featuresLink: 'Overview',
    downloadLink: 'Download',
    languageLabel: 'Choose language',
    hero: {
      eyebrow: 'Rokuga for Mac',
      title: 'Your screen in motion,',
      accent: 'just as it happens.',
      lead: 'At the speed of your display, with every Retina detail. A free screen recorder for Mac.',
      download: 'Download',
      source: 'View on GitHub',
    },
    product: {
      label: 'Interactive Rokuga area selection screen and recording toolbar',
      toolbarLabel: 'Choose a recording mode',
      record: 'Record',
      selectedArea: 'Selected Area',
      fullScreen: 'Full Screen',
      window: 'Window',
      options: 'Options',
      file: 'File',
      edit: 'Edit',
      view: 'View',
      demoLabel: 'Try it yourself',
      hint: 'Drag the selection or grab an edge to resize it.',
    },
    trust: {
      label: 'Rokuga key features',
      kicker: 'At a glance',
      title: 'Clarity. Speed. Freedom.',
      codec: 'Clear quality, more efficient files',
      frameRate: 'Frame rate matched to your display',
      resolution: 'Down to every Retina detail',
      free: 'No time limits or watermarks',
    },
    features: {
      kicker: 'Recording',
      title: 'Beyond 60 fps.',
      accent: 'At the speed of your display.',
      frameRateTitle: 'Frame rate. Motion makes the difference.',
      frameRateDescription: 'Choose 30 or 60 fps, or match your display to capture fast movement naturally.',
      matchedRate: 'fps · Matched to 144 Hz',
      codecTitle: 'H.265. Keep the clarity. Lose the weight.',
      codecDescription: 'Choose H.264 or H.265 and save to MP4 or MOV.',
      resolutionTitle: 'Up to 5K. Small details, made big.',
      resolutionDescription: 'Capture Retina pixels at resolutions up to 5120 × 2880.',
      resolutionLimit: 'Up to 5120 × 2880',
    },
    free: {
      kicker: 'Free',
      title: 'Free.',
      accent: 'It really is that simple.',
      description: 'No time limits. No watermarks. Every feature is ready to use.',
      priceValue: '$0',
      price: 'App price',
      duration: 'No time limit',
      watermark: 'No watermark',
    },
    download: {
      kicker: 'Download',
      title: 'Choose your way.',
      accent: 'Start recording.',
      lead: 'Install now with Homebrew. The Mac App Store release is coming soon.',
      appDescription: 'A native screen recorder made for Mac',
      appStoreName: 'Mac App Store',
      appStoreDescription: 'Install with one click and keep Rokuga up to date automatically.',
      appStoreButton: 'Coming soon to the App Store',
      requirements: 'macOS 15 Sequoia or later · Universal · Free',
      brewName: 'Homebrew',
      brewDescription: 'Install from the terminal with one command and update with Homebrew.',
      brewCommand: 'brew install --cask evan-choi/tap/rokuga',
      brewCopy: 'Copy',
      brewCopied: 'Copied',
      brewCopyFailed: 'Copy failed',
    },
  },
  ja: {
    pageTitle: 'Rokuga — 画面の動きを、ありのままに',
    metaDescription: 'Rokugaは、ディスプレイに合わせたフレームレート、H.265、最大5Kに対応する無料のオープンソースMac画面収録アプリです。',
    skipLink: 'コンテンツへ移動',
    navLabel: 'メインメニュー',
    brandHomeLabel: 'Rokuga ホーム',
    githubLabel: 'RokugaのGitHubリポジトリ',
    featuresLink: '概要',
    downloadLink: 'ダウンロード',
    languageLabel: '言語を選択',
    hero: {
      eyebrow: 'Rokuga for Mac',
      title: '画面の動きを、',
      accent: 'ありのままに。',
      lead: 'ディスプレイと同じ速さで、Retinaのディテールまで。Macのための無料画面収録アプリ。',
      download: 'ダウンロード',
      source: 'GitHubで見る',
    },
    product: {
      label: 'Rokugaの範囲選択画面と録画ツールバーの操作デモ',
      toolbarLabel: '録画モードを選択',
      record: '録画',
      selectedArea: '選択範囲',
      fullScreen: 'フルスクリーン',
      window: 'ウインドウ',
      options: 'オプション',
      file: 'ファイル',
      edit: '編集',
      view: '表示',
      demoLabel: '実際に動かしてみる',
      hint: '選択範囲をドラッグしたり、端をつかんでサイズを変更できます。',
    },
    trust: {
      label: 'Rokugaの主な機能',
      kicker: 'ひと目で',
      title: '鮮明さも、速さも、自由も。',
      codec: '鮮明な画質と、より効率的なファイル',
      frameRate: 'ディスプレイに合わせたフレームレート',
      resolution: 'Retinaのディテールまで',
      free: '時間制限もウォーターマークもなし',
    },
    features: {
      kicker: '収録',
      title: '60 fpsを超えて。',
      accent: '画面と同じ速さで。',
      frameRateTitle: 'フレームレート。動きでわかる違い。',
      frameRateDescription: '30 fps、60 fpsに加え、ディスプレイのリフレッシュレートに合わせて速い動きも自然に記録します。',
      matchedRate: 'fps · 144 Hzに合わせて',
      codecTitle: 'H.265。鮮明さはそのまま、ファイルは軽く。',
      codecDescription: 'H.264またはH.265を選び、MP4かMOVで保存できます。',
      resolutionTitle: '最大5K。小さなディテールまで大きく。',
      resolutionDescription: 'Retinaディスプレイのピクセルを最大5120 × 2880の解像度で記録します。',
      resolutionLimit: '最大5120 × 2880',
    },
    free: {
      kicker: '無料',
      title: '無料。',
      accent: '本当に、それだけです。',
      description: '時間制限もウォーターマークもありません。すべての機能をそのまま使えます。',
      priceValue: '¥0',
      price: 'アプリ価格',
      duration: '時間制限なし',
      watermark: 'ウォーターマークなし',
    },
    download: {
      kicker: 'ダウンロード',
      title: '好きな方法で。',
      accent: 'すぐに始めよう。',
      lead: 'Homebrewですぐにインストールできます。Mac App Store版も近日公開予定です。',
      appDescription: 'Macのためのネイティブ画面収録アプリ',
      appStoreName: 'Mac App Store',
      appStoreDescription: 'ワンクリックでインストール。アップデートも自動で。',
      appStoreButton: 'App Storeで近日公開',
      requirements: 'macOS 15 Sequoia以降 · Universal · 無料',
      brewName: 'Homebrew',
      brewDescription: 'ターミナルから1行でインストールし、Homebrewで手軽にアップデートできます。',
      brewCommand: 'brew install --cask evan-choi/tap/rokuga',
      brewCopy: 'コピー',
      brewCopied: 'コピー済み',
      brewCopyFailed: 'コピー失敗',
    },
  },
  'zh-Hans': {
    pageTitle: 'Rokuga — 屏幕每一刻，原样记录',
    metaDescription: 'Rokuga 是一款免费的开源 Mac 屏幕录制应用，支持匹配显示器帧率、H.265 和最高 5K 录制。',
    skipLink: '跳到正文',
    navLabel: '主菜单',
    brandHomeLabel: 'Rokuga 首页',
    githubLabel: 'Rokuga GitHub 仓库',
    featuresLink: '概览',
    downloadLink: '下载',
    languageLabel: '选择语言',
    hero: {
      eyebrow: 'Rokuga for Mac',
      title: '屏幕每一刻，',
      accent: '原样记录。',
      lead: '与显示器同速，Retina 细节尽收其中。一款免费的 Mac 屏幕录制应用。',
      download: '下载',
      source: '在 GitHub 上查看',
    },
    product: {
      label: 'Rokuga 区域选择界面和录制工具栏交互演示',
      toolbarLabel: '选择录制模式',
      record: '录制',
      selectedArea: '所选区域',
      fullScreen: '全屏',
      window: '窗口',
      options: '选项',
      file: '文件',
      edit: '编辑',
      view: '显示',
      demoLabel: '亲手试一试',
      hint: '拖动所选区域，或抓住边缘调整大小。',
    },
    trust: {
      label: 'Rokuga 主要功能',
      kicker: '一览',
      title: '清晰、速度、自由，缺一不可。',
      codec: '清晰画质，更高效的文件',
      frameRate: '匹配显示器的录制帧率',
      resolution: 'Retina 细节尽收其中',
      free: '无时长限制，无水印',
    },
    features: {
      kicker: '录制',
      title: '超越 60 fps。',
      accent: '与屏幕同速。',
      frameRateTitle: '帧率。动态见真章。',
      frameRateDescription: '可选 30 fps、60 fps，或匹配显示器刷新率，自然记录快速动态。',
      matchedRate: 'fps · 匹配 144 Hz',
      codecTitle: 'H.265。保留清晰，减轻体积。',
      codecDescription: '可选择 H.264 或 H.265，并保存为 MP4 或 MOV。',
      resolutionTitle: '最高 5K。小细节，大呈现。',
      resolutionDescription: '以最高 5120 × 2880 的分辨率记录 Retina 显示器像素。',
      resolutionLimit: '最高 5120 × 2880',
    },
    free: {
      kicker: '免费',
      title: '免费。',
      accent: '就是这么简单。',
      description: '没有时长限制，没有水印。所有功能都可直接使用。',
      priceValue: '¥0',
      price: '应用价格',
      duration: '无时长限制',
      watermark: '无水印',
    },
    download: {
      kicker: '下载',
      title: '选择你的方式。',
      accent: '立即开始。',
      lead: '现可通过 Homebrew 安装。Mac App Store 版本也即将推出。',
      appDescription: '专为 Mac 打造的原生屏幕录制应用',
      appStoreName: 'Mac App Store',
      appStoreDescription: '一键安装，自动保持最新版本。',
      appStoreButton: '即将登陆 App Store',
      requirements: 'macOS 15 Sequoia 或更高版本 · Universal · 免费',
      brewName: 'Homebrew',
      brewDescription: '在终端输入一行命令即可安装，并通过 Homebrew 轻松更新。',
      brewCommand: 'brew install --cask evan-choi/tap/rokuga',
      brewCopy: '复制',
      brewCopied: '已复制',
      brewCopyFailed: '复制失败',
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
