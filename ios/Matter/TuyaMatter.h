#import <TurboTuyaSpec/TurboTuyaSpec.h>
#import "TuyaEventEmitter.h"

// Phát event onMatterDeviceFound/onMatterAttestation/onMatterError → subclass TuyaEventEmitter.
@interface TuyaMatter : TuyaEventEmitter <NativeTuyaMatterSpec>

@end
