import { describe, it, expect } from '@jest/globals';
import { TuyaErrors } from '../errors';

describe('TuyaErrors.classify', () => {
  it('token expiry → token_expired, needsNewToken, retryable', () => {
    const info = TuyaErrors.classify('-55');
    expect(info.category).toBe('token_expired');
    expect(info.needsNewToken).toBe(true);
    expect(info.retryable).toBe(true);
  });

  it('code 1004 is disambiguated by domain', () => {
    expect(TuyaErrors.classify('1004', 'sdk').category).toBe('pairing_failed');
    expect(TuyaErrors.classify('1004', 'sdk').needsNewToken).toBe(true);
    expect(TuyaErrors.classify('1004', 'cloud').category).toBe('illegal_client');
  });

  it('not-logged-in → needsReLogin', () => {
    expect(TuyaErrors.classify('105').needsReLogin).toBe(true);
  });

  it('deep network range 50500–50516 (50502 = clock)', () => {
    expect(TuyaErrors.classify('50509').category).toBe('network');
    expect(TuyaErrors.classify('50502').category).toBe('ssl_clock');
  });

  it('ILLEGAL_CLIENT_ID → illegal_client', () => {
    expect(TuyaErrors.classify('ILLEGAL_CLIENT_ID').category).toBe('illegal_client');
  });

  it('accepts numeric code', () => {
    expect(TuyaErrors.classify(-60).category).toBe('mqtt');
  });

  it('unknown code falls back to unknown', () => {
    expect(TuyaErrors.classify('99999').category).toBe('unknown');
  });
});

describe('TuyaErrors.isRetryable', () => {
  it('mqtt retryable, invalid_param not', () => {
    expect(TuyaErrors.isRetryable('-60')).toBe(true);
    expect(TuyaErrors.isRetryable('-5')).toBe(false);
  });
});

describe('TuyaErrors.describe', () => {
  it('includes domain + code prefix', () => {
    expect(TuyaErrors.describe('-1')).toContain('[sdk:-1]');
  });
});
