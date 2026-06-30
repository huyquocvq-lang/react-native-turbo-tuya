#import <TurboTuyaSpec/TurboTuyaSpec.h>
#import "TuyaEventEmitter.h"

// Phát event onMeshDeviceFound/onMeshDpUpdate/onMeshStatusChanged → subclass TuyaEventEmitter.
@interface TuyaMesh : TuyaEventEmitter <NativeTuyaMeshSpec>

@end
