#import <React/RCTBridgeModule.h>

// Reject an RCTPromise with the standard TuyaError shape { code, message, domain }.
// domain: @"sdk" (on-device SDK), @"cloud" (OpenAPI), @"network". Matches src/errors.ts (TuyaErrors).
// Dùng dần cho các module mới - đừng nuốt code về @"-1".
static inline void TuyaRejectWithDomain(RCTPromiseRejectBlock reject,
                                        NSString *code,
                                        NSString *message,
                                        NSString *domain) {
  NSError *err = [NSError errorWithDomain:@"TurboTuya"
                                     code:0
                                 userInfo:@{ @"domain": (domain.length ? domain : @"sdk") }];
  reject(code.length ? code : @"unknown", message, err);
}
