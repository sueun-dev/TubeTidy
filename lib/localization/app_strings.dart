import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/plan.dart';
import '../state/ui_providers.dart';

final appStringsProvider = Provider<AppStrings>((ref) {
  final language = ref.watch(settingsLanguageProvider);
  return AppStrings(language);
});

class AppStrings {
  const AppStrings(this.language);

  final AppLanguage language;

  bool get isEn => language == AppLanguage.en;
  bool get isKo => language == AppLanguage.ko;
  bool get isJa => language == AppLanguage.ja;
  bool get isZh => language == AppLanguage.zh;
  bool get isEs => language == AppLanguage.es;

  String _t({
    required String en,
    required String ko,
    String? ja,
    String? zh,
    String? es,
  }) {
    switch (language) {
      case AppLanguage.en:
        return en;
      case AppLanguage.ko:
        return ko;
      case AppLanguage.ja:
        return ja ?? en;
      case AppLanguage.zh:
        return zh ?? en;
      case AppLanguage.es:
        return es ?? en;
    }
  }

  String get ok => _t(en: 'OK', ko: '확인', ja: 'OK', zh: '确定', es: 'OK');
  String get cancel =>
      _t(en: 'Cancel', ko: '취소', ja: 'キャンセル', zh: '取消', es: 'Cancelar');
  String get confirm =>
      _t(en: 'Confirm', ko: '확인', ja: '確認', zh: '确认', es: 'Confirmar');
  String get notice =>
      _t(en: 'Notice', ko: '알림', ja: 'お知らせ', zh: '提示', es: 'Aviso');

  String get settingsTitle =>
      _t(en: 'Settings', ko: '설정', ja: '設定', zh: '设置', es: 'Ajustes');
  String get languageTitle =>
      _t(en: 'Language', ko: '언어', ja: '言語', zh: '语言', es: 'Idioma');
  String get languageChangeTitle => _t(
        en: 'Change language?',
        ko: '언어를 변경하시겠습니까?',
        ja: '言語を変更しますか？',
        zh: '更改语言？',
        es: '¿Cambiar idioma?',
      );
  String languageName(AppLanguage target) {
    switch (target) {
      case AppLanguage.en:
        return 'English';
      case AppLanguage.ko:
        return '한국어';
      case AppLanguage.ja:
        return '日本語';
      case AppLanguage.zh:
        return '中文';
      case AppLanguage.es:
        return 'Español';
    }
  }

  String languageChangeBody(AppLanguage target) => _t(
        en: 'Switch app language to ${languageName(target)}?',
        ko: '${languageName(target)}로 앱 언어를 변경하시겠습니까?',
        ja: 'アプリ言語を${languageName(target)}に変更しますか？',
        zh: '是否将应用语言切换为${languageName(target)}？',
        es: '¿Cambiar el idioma de la app a ${languageName(target)}?',
      );

  String get accountTitle =>
      _t(en: 'Account', ko: '계정', ja: 'アカウント', zh: '账户', es: 'Cuenta');
  String get noAccount => _t(
        en: 'No account information',
        ko: '로그인 정보 없음',
        ja: 'ログイン情報なし',
        zh: '未登录',
        es: 'Sin cuenta',
      );
  String get logout => _t(
        en: 'Log out',
        ko: '로그아웃',
        ja: 'ログアウト',
        zh: '退出登录',
        es: 'Cerrar sesión',
      );
  String get requiresLogin => _t(
        en: 'Please sign in first.',
        ko: '먼저 로그인해주세요.',
        ja: '先にログインしてください。',
        zh: '请先登录。',
        es: 'Inicia sesión primero.',
      );
  String get dataTitle => _t(
        en: 'Data & storage',
        ko: '데이터 및 캐시',
        ja: 'データとストレージ',
        zh: '数据与存储',
        es: 'Datos y almacenamiento',
      );
  String get appInfoTitle => _t(
        en: 'App info',
        ko: '앱 정보',
        ja: 'アプリ情報',
        zh: '应用信息',
        es: 'Información de la app',
      );
  String get versionLabel => _t(
        en: 'Version',
        ko: '버전',
        ja: 'バージョン',
        zh: '版本',
        es: 'Versión',
      );
  String get buildLabel => _t(
        en: 'Build',
        ko: '빌드',
        ja: 'ビルド',
        zh: '构建',
        es: 'Compilación',
      );
  String get privacyPolicy => _t(
        en: 'Privacy policy',
        ko: '개인정보처리방침',
        ja: 'プライバシーポリシー',
        zh: '隐私政策',
        es: 'Política de privacidad',
      );
  String get termsOfService => _t(
        en: 'Terms of service',
        ko: '이용약관',
        ja: '利用規約',
        zh: '服务条款',
        es: 'Términos de servicio',
      );
  String get support => _t(
        en: 'Support',
        ko: '고객지원',
        ja: 'サポート',
        zh: '支持',
        es: 'Soporte',
      );
  String get openLink => _t(
        en: 'Open',
        ko: '열기',
        ja: '開く',
        zh: '打开',
        es: 'Abrir',
      );
  String get notAvailable => _t(
        en: 'Not set',
        ko: '미설정',
        ja: '未設定',
        zh: '未设置',
        es: 'No configurado',
      );
  String get clearSummaries => _t(
        en: 'Clear cached summaries',
        ko: '요약 캐시 삭제',
        ja: '要約キャッシュ削除',
        zh: '清除摘要缓存',
        es: 'Borrar caché de resúmenes',
      );
  String get clearSummariesBody => _t(
        en: 'Remove cached transcripts and summaries for this device.',
        ko: '이 기기에 저장된 자막/요약 캐시를 삭제합니다.',
        ja: 'この端末に保存された字幕/要約キャッシュを削除します。',
        zh: '删除此设备上保存的字幕/摘要缓存。',
        es: 'Elimina los subtítulos y resúmenes en caché de este dispositivo.',
      );
  String get clearHistory => _t(
        en: 'Clear watched history',
        ko: '시청 기록 삭제',
        ja: '視聴履歴を削除',
        zh: '清除观看记录',
        es: 'Borrar historial visto',
      );
  String get clearHistoryBody => _t(
        en: 'Remove the list of videos you opened on this device.',
        ko: '이 기기에 저장된 시청 기록을 삭제합니다.',
        ja: 'この端末に保存された視聴履歴を削除します。',
        zh: '删除此设备上的观看记录。',
        es: 'Elimina la lista de videos abiertos en este dispositivo.',
      );
  String get clearFavorites => _t(
        en: 'Clear favorites',
        ko: '즐겨찾기 모두 해제',
        ja: 'お気に入りを全て解除',
        zh: '清除收藏',
        es: 'Borrar favoritos',
      );
  String get clearFavoritesBody => _t(
        en: 'Remove all saved favorites in the calendar.',
        ko: '캘린더에 저장된 즐겨찾기를 모두 해제합니다.',
        ja: 'カレンダーに保存されたお気に入りを全て解除します。',
        zh: '移除日历中保存的所有收藏。',
        es: 'Elimina todos los favoritos guardados en el calendario.',
      );
  String get resetSelection => _t(
        en: 'Reset channel selection',
        ko: '채널 선택 초기화',
        ja: 'チャンネル選択をリセット',
        zh: '重置频道选择',
        es: 'Restablecer selección de canales',
      );
  String get resetSelectionBody => _t(
        en: 'Clear selected channels and reselect them again.',
        ko: '선택한 채널을 모두 초기화하고 다시 선택합니다.',
        ja: '選択したチャンネルを初期化して再選択します。',
        zh: '清空已选频道并重新选择。',
        es: 'Borra los canales seleccionados y vuelve a elegir.',
      );
  String get resetCooldown => _t(
        en: 'Reset daily change limit',
        ko: '하루 변경 제한 초기화',
        ja: '1日変更制限をリセット',
        zh: '重置每日更改限制',
        es: 'Restablecer límite diario',
      );
  String get resetCooldownBody => _t(
        en: 'Reset the one-change-per-day cooldown.',
        ko: '하루 1회 변경 제한을 초기화합니다.',
        ja: '1日1回の変更制限をリセットします。',
        zh: '重置每日一次的更改限制。',
        es: 'Restablece el límite de un cambio por día.',
      );
  String get actionDone =>
      _t(en: 'Done', ko: '완료', ja: '完了', zh: '完成', es: 'Listo');

  String get tabHome =>
      _t(en: 'Home', ko: '홈', ja: 'ホーム', zh: '主页', es: 'Inicio');
  String get tabCalendar => _t(
        en: 'Calendar',
        ko: '캘린더',
        ja: 'カレンダー',
        zh: '日历',
        es: 'Calendario',
      );
  String get tabChannels => _t(
        en: 'Channels',
        ko: '채널 추가',
        ja: 'チャンネル追加',
        zh: '添加频道',
        es: 'Canales',
      );
  String get tabPlan =>
      _t(en: 'Plan', ko: '플랜', ja: 'プラン', zh: '方案', es: 'Plan');
  String get tabSettings => _t(
        en: 'Settings',
        ko: '설정',
        ja: '設定',
        zh: '设置',
        es: 'Ajustes',
      );

  String get loginErrorTitle => _t(
        en: 'Login error',
        ko: '로그인 오류',
        ja: 'ログインエラー',
        zh: '登录错误',
        es: 'Error de inicio de sesión',
      );
  String get appTitle => _t(
        en: 'YouTube\n3-Line Summary',
        ko: 'YouTube\n3줄 요약',
        ja: 'YouTube\n3行要約',
        zh: 'YouTube\n3行总结',
        es: 'YouTube\nResumen en 3 líneas',
      );
  String get appSubtitle => _t(
        en: 'Get the latest uploads from your subscriptions\nsummarized in 3 lines.',
        ko: '구독 채널의 최신 업로드를\n3줄 요약으로 바로 확인하세요.',
        ja: '登録チャンネルの最新動画を\n3行で要約して確認できます。',
        zh: '快速查看订阅频道最新上传的\n3行摘要。',
        es: 'Mira lo último de tus suscripciones\nresumido en 3 líneas.',
      );
  String get featureSyncTitle => _t(
        en: 'Auto-sync subscriptions',
        ko: '구독 채널 자동 동기화',
        ja: '登録チャンネル自動同期',
        zh: '订阅频道自动同步',
        es: 'Sincronización automática',
      );
  String get featureSyncSubtitle => _t(
        en: 'Import your latest channels immediately after login.',
        ko: '로그인 후 연결 즉시 최신 채널을 불러옵니다.',
        ja: 'ログイン後すぐに最新チャンネルを取得します。',
        zh: '登录后立即导入最新频道。',
        es: 'Importa tus canales al iniciar sesión.',
      );
  String get featureSummaryTitle => _t(
      en: '3-line summary',
      ko: '핵심만 3줄 요약',
      ja: '3行の要約',
      zh: '3行核心摘要',
      es: 'Resumen en 3 líneas');
  String get featureSummarySubtitle => _t(
        en: 'Skim long videos quickly with concise highlights.',
        ko: '긴 영상도 핵심만 빠르게 읽어보세요.',
        ja: '長い動画も要点だけ素早く確認。',
        zh: '长视频也能快速看重点。',
        es: 'Lee lo esencial de videos largos rápidamente.',
      );
  String get featureArchiveTitle => _t(
        en: 'Archiving calendar',
        ko: '아카이빙 캘린더',
        ja: 'アーカイブカレンダー',
        zh: '归档日历',
        es: 'Calendario de archivos',
      );
  String get featureArchiveSubtitle => _t(
        en: 'Collect saved summaries by date.',
        ko: '저장한 요약을 날짜별로 모아볼 수 있어요.',
        ja: '保存した要約を日付でまとめて表示。',
        zh: '按日期查看保存的摘要。',
        es: 'Consulta resúmenes guardados por fecha.',
      );
  String get signInWithGoogle => _t(
        en: 'Sign in with Google',
        ko: 'Google로 로그인',
        ja: 'Googleでログイン',
        zh: '使用 Google 登录',
        es: 'Iniciar con Google',
      );
  String get loginHelper => _t(
        en: 'Signing in will link your YouTube account automatically.',
        ko: '로그인하면 YouTube 계정이 자동으로 연동됩니다.',
        ja: 'ログインするとYouTubeアカウントが自動で連携됩니다。',
        zh: '登录后会自动关联你的 YouTube 账号。',
        es: 'Al iniciar sesión se vincula tu cuenta de YouTube.',
      );

  String get connectTitle => _t(
        en: 'Connect YouTube',
        ko: 'YouTube 연동',
        ja: 'YouTube連携',
        zh: '连接 YouTube',
        es: 'Conectar YouTube',
      );
  String get connectCardTitle => _t(
        en: 'Sync subscriptions',
        ko: '구독 채널 동기화',
        ja: '登録チャンネル同期',
        zh: '同步订阅频道',
        es: 'Sincronizar suscripciones',
      );
  String get connectCardSubtitle => _t(
        en: 'Connect your YouTube account to import subscriptions and latest uploads.',
        ko: 'YouTube 계정을 연동하면 구독 채널과 최신 업로드 영상을 가져올 수 있어요.',
        ja: 'YouTubeアカウントを連携して登録チャンネルと最新動画を取得します。',
        zh: '连接 YouTube 以导入订阅和最新上传。',
        es: 'Conecta tu cuenta para importar suscripciones y novedades.',
      );
  String get permissionReadSubscriptions => _t(
        en: 'Read subscription list',
        ko: '구독 채널 목록 읽기',
        ja: '登録チャンネル一覧の取得',
        zh: '读取订阅列表',
        es: 'Leer lista de suscripciones',
      );
  String get permissionReadMetadata => _t(
        en: 'Read upload metadata',
        ko: '업로드 영상 메타데이터 읽기',
        ja: 'アップロード動画のメタデータ取得',
        zh: '读取上传元数据',
        es: 'Leer metadatos de videos',
      );
  String get permissionAnalytics => _t(
        en: 'Anonymous usage analytics for summary quality',
        ko: '요약 품질 개선을 위한 익명 분석',
        ja: '要約品質改善のための匿名分析',
        zh: '用于改进摘要质量的匿名分析',
        es: 'Analíticas anónimas para mejorar resúmenes',
      );
  String get connectButton => _t(
        en: 'Connect YouTube account',
        ko: 'YouTube 계정 연동',
        ja: 'YouTubeアカウント連携',
        zh: '连接 YouTube 账号',
        es: 'Conectar cuenta de YouTube',
      );
  String get connectFooter => _t(
        en: 'You can disconnect anytime.',
        ko: '연동 후 언제든지 해제할 수 있습니다.',
        ja: 'いつでも解除できます。',
        zh: '你可以随时断开。',
        es: 'Puedes desconectar cuando quieras.',
      );

  String get channelSelectionTitle => _t(
        en: 'Select channels',
        ko: '채널 선택',
        ja: 'チャンネル選択',
        zh: '选择频道',
        es: 'Seleccionar canales',
      );
  String get searchPlaceholder => _t(
        en: 'Search channels',
        ko: '채널 이름 검색',
        ja: 'チャンネル検索',
        zh: '搜索频道',
        es: 'Buscar canales',
      );
  String totalCount(int count) => _t(
        en: 'Total $count',
        ko: '총 $count개',
        ja: '合計 $count',
        zh: '共 $count 个',
        es: 'Total $count',
      );
  String get noSearchResults => _t(
        en: 'No results found.',
        ko: '검색 결과가 없습니다.',
        ja: '検索結果がありません。',
        zh: '没有搜索结果。',
        es: 'No se encontraron resultados.',
      );
  String get loadingSubscriptions => _t(
        en: 'Loading subscriptions',
        ko: '구독 채널 불러오는 중',
        ja: '登録チャンネル読み込み中',
        zh: '正在加载订阅频道',
        es: 'Cargando suscripciones',
      );
  String get noSubscriptions => _t(
        en: 'No subscriptions found.',
        ko: '구독 채널이 없습니다.',
        ja: '登録チャンネルがありません。',
        zh: '没有订阅频道。',
        es: 'No hay suscripciones.',
      );
  String get syncingMessage => _t(
        en: 'Signing in and syncing YouTube...',
        ko: 'Google 로그인과 YouTube 동기화를 진행하고 있어요.',
        ja: 'ログインとYouTube同期中です。',
        zh: '正在登录并同步 YouTube…',
        es: 'Iniciando sesión y sincronizando YouTube…',
      );
  String get failedSubscriptions => _t(
        en: 'Could not load subscriptions. Please try again.',
        ko: 'YouTube 구독 목록을 불러오지 못했어요. 다시 시도해주세요.',
        ja: '登録チャンネルを取得できませんでした。再試行してください。',
        zh: '无法加载订阅列表，请重试。',
        es: 'No se pudieron cargar las suscripciones. Intenta de nuevo.',
      );
  String get reload =>
      _t(en: 'Retry', ko: '다시 불러오기', ja: '再読み込み', zh: '重试', es: 'Reintentar');
  String get selectionComplete => _t(
        en: 'Finish selection',
        ko: '채널 선택 완료',
        ja: '選択完了',
        zh: '完成选择',
        es: 'Finalizar selección',
      );
  String get upgradeLabel =>
      _t(en: 'Upgrade', ko: '업그레이드', ja: 'アップグレード', zh: '升级', es: 'Actualizar');
  String channelCountLabel(int count) => _t(
        en: '$count channels',
        ko: '$count 채널',
        ja: '$count チャンネル',
        zh: '$count 个频道',
        es: '$count canales',
      );
  String selectedCountLabel(int count, String limitLabel) => _t(
        en: 'Selected $count / $limitLabel',
        ko: '선택됨 $count / $limitLabel',
        ja: '選択 $count / $limitLabel',
        zh: '已选 $count / $limitLabel',
        es: 'Seleccionados $count / $limitLabel',
      );
  String selectionFooter(bool completed) => _t(
        en: completed
            ? 'You can change channels once per day.'
            : 'Selection limits are based on your subscriptions.',
        ko: completed
            ? '채널 변경은 하루에 1회만 가능합니다.'
            : '구독 수에 따라 선택 가능한 채널 수가 자동으로 조정됩니다.',
        ja: completed ? 'チャンネル変更は1日1回のみ可能です。' : '登録数に応じて選択上限が決まります。',
        zh: completed ? '频道每天只能更改一次。' : '选择上限会根据订阅数自动调整。',
        es: completed
            ? 'Puedes cambiar canales una vez al día.'
            : 'El límite depende de tus suscripciones.',
      );
  String get limitBanner => _t(
        en: 'Channel limit reached. Remove one to add another.',
        ko: '채널 한도에 도달했습니다. 다른 채널을 하나 해제한 뒤 추가해주세요.',
        ja: 'チャンネル上限に達しました。別のチャンネルを解除してください。',
        zh: '已达频道上限，请先取消一个。',
        es: 'Límite alcanzado. Quita uno para agregar otro.',
      );

  String get homeTitle =>
      _t(en: 'Summary', ko: '요약 홈', ja: '要約', zh: '摘要', es: 'Resumen');
  String planTag(String planName, String priceLabel) => _t(
        en: '$planName Plan · $priceLabel',
        ko: '$planName 플랜 · $priceLabel',
        ja: '$planName プラン · $priceLabel',
        zh: '$planName 方案 · $priceLabel',
        es: '$planName Plan · $priceLabel',
      );
  String selectedChannelsLabel(int count, String limitLabel) => _t(
        en: 'Selected $count / $limitLabel',
        ko: '선택 채널 $count / $limitLabel',
        ja: '選択チャンネル $count / $limitLabel',
        zh: '已选频道 $count / $limitLabel',
        es: 'Canales $count / $limitLabel',
      );
  String get todaySummary => _t(
        en: 'Today in Tech/Trends',
        ko: '오늘의 기술/트렌드 요약',
        ja: '今日の技術/トレンド要約',
        zh: '今日技术/趋势摘要',
        es: 'Resumen de tecnología/tendencias',
      );
  String get summaryLabel =>
      _t(en: 'Summaries', ko: '요약', ja: '要約', zh: '摘要', es: 'Resúmenes');
  String get savedLabel =>
      _t(en: 'Saved', ko: '별표', ja: '保存', zh: '收藏', es: 'Guardados');
  String get channelFilter => _t(
        en: 'Channel filter',
        ko: '채널 필터',
        ja: 'チャンネルフィルタ',
        zh: '频道筛选',
        es: 'Filtro de canales',
      );
  String get manageChannels => _t(
        en: 'Manage channels',
        ko: '채널 선택 관리',
        ja: 'チャンネル管理',
        zh: '管理频道',
        es: 'Gestionar canales',
      );
  String get all => _t(en: 'All', ko: '전체', ja: 'すべて', zh: '全部', es: 'Todos');
  String get emptySummaries => _t(
        en: 'No summaries yet.',
        ko: '요약된 영상이 아직 없어요.',
        ja: '要約された動画がありません。',
        zh: '还没有摘要视频。',
        es: 'Aún no hay resúmenes.',
      );
  String cooldownLabel(DateTime date) => _t(
        en: 'Cooldown · Next change: ${formatMonthDay(date)}',
        ko: '채널 변경 쿨타임 · 다음 변경 가능: ${formatMonthDay(date)}',
        ja: 'クールダウン · 次の変更: ${formatMonthDay(date)}',
        zh: '冷却中 · 下次可更改: ${formatMonthDay(date)}',
        es: 'Espera · Próximo cambio: ${formatMonthDay(date)}',
      );
  String get unknownChannel => _t(
        en: 'Unknown',
        ko: '알 수 없음',
        ja: '不明',
        zh: '未知',
        es: 'Desconocido',
      );

  String get metaSummary => _t(
      en: '3-line summary',
      ko: '3줄 요약',
      ja: '3行要約',
      zh: '3行摘要',
      es: 'Resumen en 3 líneas');
  String get metaCaptions =>
      _t(en: 'Captions', ko: '자막', ja: '字幕', zh: '字幕', es: 'Subtítulos');
  String get metaSpeech =>
      _t(en: 'Speech', ko: '음성 인식', ja: '音声認識', zh: '语音识别', es: 'Voz');
  String get metaPartial => _t(
      en: 'Partial captions',
      ko: '자막 일부',
      ja: '字幕一部',
      zh: '部分字幕',
      es: 'Subtítulos parciales');
  String get generatingTranscript => _t(
        en: 'Generating transcript...',
        ko: '자막/음성 텍스트 생성 중',
        ja: '字幕/音声テキスト生成中',
        zh: '正在生成字幕/语音文本…',
        es: 'Generando transcripción…',
      );
  String get queued => _t(
      en: 'Queued for summary',
      ko: '요약 대기 중',
      ja: '要約待ち',
      zh: '等待摘要',
      es: 'En cola para resumen');
  String get notGenerated => _t(
        en: 'Summary has not been generated yet.',
        ko: '요약이 아직 생성되지 않았습니다.',
        ja: '要約がまだ生成されていません。',
        zh: '摘要尚未生成。',
        es: 'El resumen aún no se ha generado.',
      );
  String get summarize =>
      _t(en: 'Summarize', ko: '요약하기', ja: '要約する', zh: '生成摘要', es: 'Resumir');
  String get retrySummarize => _t(
        en: 'Try again',
        ko: '다시 요약하기',
        ja: '再試行',
        zh: '重试',
        es: 'Reintentar',
      );
  String get watchVideo => _t(
        en: 'Watch on YouTube',
        ko: '영상 보러가기',
        ja: 'YouTubeで見る',
        zh: '在 YouTube 观看',
        es: 'Ver en YouTube',
      );

  String get selected =>
      _t(en: 'Selected', ko: '선택됨', ja: '選択済み', zh: '已选', es: 'Seleccionado');
  String get selectable =>
      _t(en: 'Available', ko: '선택 가능', ja: '選択可能', zh: '可选择', es: 'Disponible');
  String channelSelectSemantics(String title) => _t(
        en: 'Select channel $title',
        ko: '$title 채널 선택',
        ja: '$title チャンネル選択',
        zh: '选择频道 $title',
        es: 'Seleccionar canal $title',
      );

  String get calendarTitle => _t(
        en: 'Calendar',
        ko: '캘린더',
        ja: 'カレンダー',
        zh: '日历',
        es: 'Calendario',
      );
  String monthSavedLabel(int count) => _t(
        en: 'Saved this month',
        ko: '이번 달 저장',
        ja: '今月の保存',
        zh: '本月保存',
        es: 'Guardados este mes',
      );
  String totalSavedLabel(int count) => _t(
        en: 'Total saved',
        ko: '전체 저장',
        ja: '総保存',
        zh: '总保存',
        es: 'Total guardados',
      );
  String monthVideosLabel(int count) => _t(
        en: 'Videos this month',
        ko: '이번 달 영상',
        ja: '今月の動画',
        zh: '本月视频',
        es: 'Videos de este mes',
      );
  String totalVideosLabel(int count) => _t(
        en: 'Total videos',
        ko: '전체 영상',
        ja: '全動画',
        zh: '全部视频',
        es: 'Total de videos',
      );
  String get emptySaved => _t(
        en: 'No saved summaries yet.',
        ko: '저장된 요약이 아직 없어요.',
        ja: '保存された要約がありません。',
        zh: '暂无保存的摘要。',
        es: 'Aún no hay resúmenes guardados.',
      );
  String get emptyVideos => _t(
        en: 'No videos yet.',
        ko: '영상이 아직 없어요.',
        ja: 'まだ動画がありません。',
        zh: '暂无视频。',
        es: 'Aún no hay videos.',
      );
  String get calendarFilterTitle => _t(
        en: 'Channel filter',
        ko: '채널 필터',
        ja: 'チャンネルフィルタ',
        zh: '频道筛选',
        es: 'Filtro de canales',
      );
  String get removeFavorite => _t(
        en: 'Remove from favorites',
        ko: '즐겨찾기 해제',
        ja: 'お気に入り解除',
        zh: '取消收藏',
        es: 'Quitar de favoritos',
      );

  List<String> get weekdayLabels {
    switch (language) {
      case AppLanguage.en:
        return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      case AppLanguage.ko:
        return const ['월', '화', '수', '목', '금', '토', '일'];
      case AppLanguage.ja:
        return const ['月', '火', '水', '木', '金', '土', '日'];
      case AppLanguage.zh:
        return const ['一', '二', '三', '四', '五', '六', '日'];
      case AppLanguage.es:
        return const ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    }
  }

  String formatSelectedDate(DateTime date) {
    final month = date.month;
    final day = date.day;
    switch (language) {
      case AppLanguage.en:
        return '${_enMonthsShort[month - 1]} ${_pad2(day)}';
      case AppLanguage.ko:
        return '${_pad2(month)}월 ${_pad2(day)}일';
      case AppLanguage.ja:
        return '$month月$day日';
      case AppLanguage.zh:
        return '$month月$day日';
      case AppLanguage.es:
        return '$day ${_esMonthsShort[month - 1]}';
    }
  }

  String formatMonthYear(DateTime date) {
    final month = date.month;
    final year = date.year;
    switch (language) {
      case AppLanguage.en:
        return '${_enMonths[month - 1]} $year';
      case AppLanguage.ko:
        return '$year년 ${_pad2(month)}월';
      case AppLanguage.ja:
        return '$year年$month月';
      case AppLanguage.zh:
        return '$year年$month月';
      case AppLanguage.es:
        return '${_esMonths[month - 1]} $year';
    }
  }

  String formatMonthDay(DateTime date) {
    final month = date.month;
    final day = date.day;
    switch (language) {
      case AppLanguage.en:
        return '${_enMonthsShort[month - 1]} $day';
      case AppLanguage.ko:
        return '$month월 $day일';
      case AppLanguage.ja:
        return '$month月$day日';
      case AppLanguage.zh:
        return '$month月$day日';
      case AppLanguage.es:
        return '$day ${_esMonthsShort[month - 1]}';
    }
  }

  String get planTitle => _t(
        en: 'Plan',
        ko: '플랜 관리',
        ja: 'プラン管理',
        zh: '方案管理',
        es: 'Plan',
      );
  String get planIntro => _t(
        en: 'Change your channel limits and pricing.',
        ko: '채널 선택 한도 및 요금제를 변경하세요.',
        ja: 'チャンネル上限と料金を変更します。',
        zh: '更改频道上限和价格方案。',
        es: 'Cambia límites y precios del plan.',
      );
  String get planChangeTitle => _t(
        en: 'Plan updated',
        ko: '플랜 변경 완료',
        ja: 'プラン更新完了',
        zh: '方案已更新',
        es: 'Plan actualizado',
      );
  String planChangedBody(String name) => _t(
        en: 'Switched to $name plan.',
        ko: '$name 플랜으로 변경되었습니다.',
        ja: '$name プランに変更しました。',
        zh: '已切换到 $name 方案。',
        es: 'Cambiado al plan $name.',
      );
  String get billingTitle => _t(
        en: 'Billing & receipts',
        ko: '결제/영수증',
        ja: '課金/領収書',
        zh: '账单与收据',
        es: 'Facturación y recibos',
      );
  String get billingSubtitle => _t(
        en: 'You can view receipts and renewal info after iOS in-app purchase integration.',
        ko: 'iOS 인앱 결제 연동 후 영수증과 갱신 정보를 확인할 수 있습니다.',
        ja: 'iOSのアプリ内課金連携後に領収書と更新情報を確認できます。',
        zh: '接入 iOS 内购后可查看收据和续订信息。',
        es: 'Tras integrar IAP en iOS podrás ver recibos y renovaciones.',
      );
  String get viewReceipt => _t(
        en: 'View receipt',
        ko: '영수증 보기',
        ja: '領収書を見る',
        zh: '查看收据',
        es: 'Ver recibo',
      );
  String get manageSubscription => _t(
        en: 'Manage subscription',
        ko: '구독 관리',
        ja: 'サブスク管理',
        zh: '管理订阅',
        es: 'Gestionar suscripción',
      );

  String planName(PlanTier tier) {
    switch (tier) {
      case PlanTier.free:
        return _t(en: 'Free', ko: '무료', ja: '無料', zh: '免费', es: 'Gratis');
      case PlanTier.starter:
        return _t(en: 'Plus', ko: 'Plus', ja: 'Plus', zh: 'Plus', es: 'Plus');
      case PlanTier.growth:
        return _t(en: 'Pro', ko: 'Pro', ja: 'Pro', zh: 'Pro', es: 'Pro');
      case PlanTier.unlimited:
        return _t(
            en: 'Unlimited',
            ko: 'Unlimited',
            ja: 'Unlimited',
            zh: 'Unlimited',
            es: 'Unlimited');
      case PlanTier.lifetime:
        return _t(
            en: 'Unlimited',
            ko: 'Unlimited',
            ja: 'Unlimited',
            zh: 'Unlimited',
            es: 'Unlimited');
    }
  }

  String planPriceLabel(PlanTier tier) {
    switch (tier) {
      case PlanTier.free:
        return _t(en: 'Free', ko: '무료', ja: '無料', zh: '免费', es: 'Gratis');
      case PlanTier.starter:
        return _t(
            en: '\$0.99/mo',
            ko: '\$0.99/월',
            ja: '\$0.99/月',
            zh: '\$0.99/月',
            es: '\$0.99/mes');
      case PlanTier.growth:
        return _t(
            en: '\$1.99/mo',
            ko: '\$1.99/월',
            ja: '\$1.99/月',
            zh: '\$1.99/月',
            es: '\$1.99/mes');
      case PlanTier.unlimited:
        return _t(
            en: '\$2.99/mo',
            ko: '\$2.99/월',
            ja: '\$2.99/月',
            zh: '\$2.99/月',
            es: '\$2.99/mes');
      case PlanTier.lifetime:
        return _t(
            en: '\$19.99 (lifetime)',
            ko: '\$19.99 (평생)',
            ja: '\$19.99 (永久)',
            zh: '\$19.99 (永久)',
            es: '\$19.99 (de por vida)');
    }
  }

  String planLimitLabel(Plan plan) {
    final limit = plan.channelLimit;
    if (limit == null) {
      return _t(
          en: 'Unlimited channels',
          ko: '무제한 채널',
          ja: '無制限チャンネル',
          zh: '无限频道',
          es: 'Canales ilimitados');
    }
    return _t(
        en: '$limit channels',
        ko: '$limit 채널',
        ja: '$limit チャンネル',
        zh: '$limit 个频道',
        es: '$limit canales');
  }

  String get planInUse =>
      _t(en: 'In use', ko: '사용 중', ja: '使用中', zh: '使用中', es: 'En uso');
  String get currentPlan => _t(
      en: 'Current plan',
      ko: '현재 플랜',
      ja: '現在のプラン',
      zh: '当前方案',
      es: 'Plan actual');
  String get selectPlan => _t(
      en: 'Choose this plan',
      ko: '이 플랜 선택',
      ja: 'このプランを選択',
      zh: '选择此方案',
      es: 'Elegir este plan');
  String get planSelectedChannelsLabel =>
      _t(en: 'Channels', ko: '채널 선택', ja: 'チャンネル', zh: '频道', es: 'Canales');

  String get iapMissingProductId => _t(
        en: 'In-app purchase product ID is missing.',
        ko: '인앱 결제 상품 ID가 설정되지 않았습니다.',
        ja: 'アプリ内課金のプロダクトIDが未設定です。',
        zh: '未设置应用内购商品 ID。',
        es: 'Falta el ID del producto de compras dentro de la app.',
      );
  String get iapUnavailable => _t(
        en: 'In-app purchases are not available on this device.',
        ko: '이 기기에서는 인앱 결제를 사용할 수 없습니다.',
        ja: 'この端末ではアプリ内課金が利用できません。',
        zh: '此设备无法使用应用内购。',
        es: 'Las compras dentro de la app no están disponibles en este dispositivo.',
      );
  String get iapFailed => _t(
        en: 'Purchase was not completed. Please try again.',
        ko: '결제가 완료되지 않았습니다. 다시 시도해주세요.',
        ja: '購入が完了しませんでした。再試行してください。',
        zh: '购买未完成，请重试。',
        es: 'La compra no se completó. Inténtalo de nuevo.',
      );
  String get iapRestoreUnavailable => _t(
        en: 'Restore is available on iOS only.',
        ko: '복원은 iOS에서만 사용할 수 있습니다.',
        ja: '復元はiOSのみ対応です。',
        zh: '仅支持在 iOS 上恢复购买。',
        es: 'La restauración solo está disponible en iOS.',
      );
  String get iapRestoreEmpty => _t(
        en: 'No purchases to restore.',
        ko: '복원할 구매 내역이 없습니다.',
        ja: '復元できる購入履歴がありません。',
        zh: '没有可恢复的购买记录。',
        es: 'No hay compras para restaurar.',
      );
  String get iapRestoreNotFound => _t(
        en: 'No matching plan found in purchases.',
        ko: '복원할 플랜을 찾지 못했습니다.',
        ja: '購入履歴に一致するプランが見つかりません。',
        zh: '未找到匹配的方案。',
        es: 'No se encontró un plan coincidente.',
      );

  static const List<String> _enMonths = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static const List<String> _enMonthsShort = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static const List<String> _esMonths = [
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ];

  static const List<String> _esMonthsShort = [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];

  static String _pad2(int value) => value.toString().padLeft(2, '0');
}
