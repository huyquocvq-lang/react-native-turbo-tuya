// TuyaErrors — JS-only classifier for Tuya Home SDK error codes (static table, no native calls).
// Source: docs/research/tuya-home-sdk-error-codes.md (cited). Lets the app decide retry / re-login /
// new-token / user message from a (code, domain) pair without round-tripping to native.
//
// All native modules SHOULD reject with the TuyaError shape { code, message, domain }
// (see common/TuyaReject.kt + ios/Common/TuyaReject.h). Never collapse codes to "-1".

export type TuyaErrorDomain = 'sdk' | 'cloud' | 'network';

export type TuyaErrorCategory =
  | 'not_initialized'
  | 'not_logged_in'
  | 'invalid_param'
  | 'token_expired'
  | 'pairing_failed'
  | 'pairing_timeout'
  | 'dp_unsupported'
  | 'mqtt'
  | 'device_offline'
  | 'network'
  | 'ssl_clock'
  | 'account'
  | 'illegal_client'
  | 'permission'
  | 'unknown';

/** Normalized error shape every module rejects with. */
export type TuyaError = {
  code: string;
  message: string;
  domain: TuyaErrorDomain;
};

export type TuyaErrorInfo = {
  code: string;
  domain: TuyaErrorDomain;
  category: TuyaErrorCategory;
  retryable: boolean;
  /** caller should fetch a fresh activator token before retrying (pairing/control). */
  needsNewToken: boolean;
  /** session is gone — route the user back to login. */
  needsReLogin: boolean;
  /** i18n key the app maps to a user-facing message. */
  userMessageKey: string;
};

const RETRYABLE: Record<TuyaErrorCategory, boolean> = {
  not_initialized: false,
  not_logged_in: false,
  invalid_param: false,
  token_expired: true,
  pairing_failed: false,
  pairing_timeout: true,
  dp_unsupported: false,
  mqtt: true,
  device_offline: false,
  network: true,
  ssl_clock: false,
  account: false,
  illegal_client: false,
  permission: false,
  unknown: false,
};

const MESSAGE_KEY: Record<TuyaErrorCategory, string> = {
  not_initialized: 'error.tuya.not_initialized',
  not_logged_in: 'error.tuya.not_logged_in',
  invalid_param: 'error.tuya.invalid_param',
  token_expired: 'error.tuya.token_expired',
  pairing_failed: 'error.tuya.pairing_failed',
  pairing_timeout: 'error.tuya.pairing_timeout',
  dp_unsupported: 'error.tuya.dp_unsupported',
  mqtt: 'error.tuya.connection',
  device_offline: 'error.tuya.device_offline',
  network: 'error.tuya.network',
  ssl_clock: 'error.tuya.clock',
  account: 'error.tuya.account',
  illegal_client: 'error.tuya.illegal_client',
  permission: 'error.tuya.permission',
  unknown: 'error.tuya.unknown',
};

// Default (on-device SDK) code -> category. See research note for full table.
const SDK_CODES: Record<string, TuyaErrorCategory> = {
  '-1': 'not_initialized',
  '-3': 'network',
  '-5': 'invalid_param',
  '-33': 'token_expired', // get activator token timeout
  '-55': 'token_expired', // token expired
  '-56': 'token_expired', // token mismatch
  '-57': 'token_expired', // token verify fail
  '-58': 'mqtt', '-59': 'mqtt', '-60': 'mqtt', '-61': 'mqtt',
  '-62': 'mqtt', '-63': 'mqtt', '-64': 'mqtt', '-65': 'mqtt', '-66': 'mqtt',
  '-1400': 'dp_unsupported', // DP not supported / wrong schema
  '-1401': 'dp_unsupported', // DP wrong format
  '-1402': 'network', // query DP timeout
  '-10001': 'device_offline',
  '-10006': 'device_offline',
  '101': 'network',
  '102': 'network',
  '103': 'ssl_clock',
  '104': 'ssl_clock', // device clock wrong
  '105': 'not_logged_in',
  '106': 'network',
  '1001': 'pairing_failed', '1002': 'pairing_failed', '1003': 'pairing_failed',
  '1004': 'pairing_failed', // get pairing token fail (on-device)
  '1005': 'pairing_failed', '1007': 'pairing_failed',
  '1006': 'pairing_timeout',
  '1100': 'invalid_param',
  '1101': 'account', // OTP wrong
  '1102': 'invalid_param',
  '10201': 'network',
  '10202': 'network',
  '10203': 'device_offline',
  '11001': 'dp_unsupported', '11002': 'dp_unsupported', '11003': 'dp_unsupported',
  '11004': 'dp_unsupported', '11005': 'dp_unsupported', '11006': 'dp_unsupported',
  '11007': 'dp_unsupported', '11008': 'dp_unsupported', '11009': 'dp_unsupported',
  '12001': 'unknown', '12002': 'unknown', '12003': 'token_expired', '12004': 'unknown',
};

// Cloud OpenAPI codes override when domain === 'cloud' (some clash with on-device meaning, e.g. 1004).
const CLOUD_CODES: Record<string, TuyaErrorCategory> = {
  '1001': 'illegal_client', // secret invalid
  '1004': 'illegal_client', // sign invalid
  '1005': 'illegal_client', // clientId invalid
  '1010': 'token_expired',
  '1011': 'token_expired',
  '1106': 'permission',
  '2006': 'account', '2021': 'account', '2023': 'account',
  '2401': 'account', '2056': 'account',
};

function categoryOf(code: string, domain: TuyaErrorDomain): TuyaErrorCategory {
  if (code.toUpperCase().includes('ILLEGAL_CLIENT')) return 'illegal_client';
  // Local vars: under noUncheckedIndexedAccess a repeated `MAP[code]` isn't narrowed.
  const cloud = domain === 'cloud' ? CLOUD_CODES[code] : undefined;
  if (cloud) return cloud;
  const sdk = SDK_CODES[code];
  if (sdk) return sdk;
  // Deep network range 50500–50516 (50502 = clock/cert time wrong).
  const n = Number(code);
  if (Number.isInteger(n) && n >= 50500 && n <= 50516) {
    return n === 50502 ? 'ssl_clock' : 'network';
  }
  return 'unknown';
}

/** Classify a raw error code into actionable info. `domain` disambiguates clashing codes. */
export function classify(
  code: string | number,
  domain: TuyaErrorDomain = 'sdk'
): TuyaErrorInfo {
  const c = String(code).trim();
  const category = categoryOf(c, domain);
  return {
    code: c,
    domain,
    category,
    retryable: RETRYABLE[category],
    needsNewToken:
      category === 'token_expired' || (domain !== 'cloud' && c === '1004'),
    needsReLogin: category === 'not_logged_in',
    userMessageKey: MESSAGE_KEY[category],
  };
}

/** Quick predicate: is this error worth an automatic retry? */
export function isRetryable(
  code: string | number,
  domain: TuyaErrorDomain = 'sdk'
): boolean {
  return classify(code, domain).retryable;
}

/** Human-readable (Vietnamese) description for logs/debug. App UI should use userMessageKey for i18n. */
export function describe(
  code: string | number,
  domain: TuyaErrorDomain = 'sdk'
): string {
  const info = classify(code, domain);
  const text: Record<TuyaErrorCategory, string> = {
    not_initialized: 'SDK chưa init — gọi Tuya.initSdk() trước.',
    not_logged_in: 'Chưa đăng nhập — cần login lại.',
    invalid_param: 'Tham số không hợp lệ.',
    token_expired: 'Token hết hạn/không khớp — lấy token mới rồi thử lại.',
    pairing_failed: 'Ghép nối thất bại.',
    pairing_timeout: 'Ghép nối quá thời gian — thử lại.',
    dp_unsupported: 'DP không hỗ trợ hoặc sai kiểu/giá trị.',
    mqtt: 'Mất kết nối realtime (MQTT) — thử lại.',
    device_offline: 'Thiết bị offline/không kết nối.',
    network: 'Lỗi mạng — kiểm tra kết nối rồi thử lại.',
    ssl_clock: 'Đồng hồ thiết bị/máy sai hoặc lỗi chứng chỉ SSL.',
    account: 'Lỗi tài khoản (mã OTP/email/mật khẩu...).',
    illegal_client: 'Sai AppKey/Secret hoặc package/bundleId/SHA-256/Data Center.',
    permission: 'Không đủ quyền thực hiện.',
    unknown: 'Lỗi không xác định.',
  };
  return `[${info.domain}:${info.code}] ${text[info.category]}`;
}

export const TuyaErrors = { classify, isRetryable, describe };
