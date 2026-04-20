#import "TorchModule.h"

// Stub implementation — LibTorch-Lite integration requires C++ bridging.
// When built with LibTorch-Lite linked, replace these stubs with actual
// torch::jit::load() / forward() calls.

#pragma mark - Tensor

@implementation Tensor {
    NSArray<NSNumber *> *_data;
}

- (instancetype)initWithShape:(NSArray<NSNumber *> *)shape
                         data:(NSArray<NSNumber *> *)data
                         type:(TorchTensorType)type {
    self = [super init];
    if (self) {
        _shape = [shape copy];
        _data = [data copy];
        _type = type;
    }
    return self;
}

- (NSArray<NSNumber *> *)floatData {
    return _data;
}

@end

#pragma mark - TorchModule

@implementation TorchModule

+ (nullable instancetype)moduleWithFileAtPath:(NSString *)path {
    return [[self alloc] initWithFileAtPath:path];
}

- (nullable instancetype)initWithFileAtPath:(NSString *)path {
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        NSLog(@"[TorchModule] File not found: %@", path);
        return nil;
    }
    self = [super init];
    if (self) {
        NSLog(@"[TorchModule] Loaded (stub): %@", path.lastPathComponent);
    }
    return self;
}

- (nullable Tensor *)predictWithSingle:(Tensor *)input {
    NSLog(@"[TorchModule] predictWithSingle: stub — returning nil");
    return nil;
}

- (nullable Tensor *)predictWith:(NSArray<Tensor *> *)inputs {
    NSLog(@"[TorchModule] predictWith: stub — returning nil");
    return nil;
}

@end
