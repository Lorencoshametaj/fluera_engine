#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Tensor data type enum
typedef NS_ENUM(NSInteger, TorchTensorType) {
    TorchTensorTypeFloat = 0,
    TorchTensorTypeLong = 1,
    TorchTensorTypeDouble = 2,
    TorchTensorTypeInt = 3,
};

/// Lightweight wrapper around a PyTorch Tensor for Swift interop
@interface Tensor : NSObject

@property (nonatomic, readonly) NSArray<NSNumber *> *shape;
@property (nonatomic, readonly) TorchTensorType type;

- (instancetype)initWithShape:(NSArray<NSNumber *> *)shape
                         data:(NSArray<NSNumber *> *)data
                         type:(TorchTensorType)type;

/// Returns the float data backing this tensor
- (NSArray<NSNumber *> *)floatData;

@end

/// Objective-C wrapper for PyTorch Mobile TorchModule
@interface TorchModule : NSObject

/// Load a module from a .ptl file on disk
+ (nullable instancetype)moduleWithFileAtPath:(NSString *)path;

/// Failable init from file path
- (nullable instancetype)initWithFileAtPath:(NSString *)path;

/// Run inference with a single input tensor
- (nullable Tensor *)predictWithSingle:(Tensor *)input;

/// Run inference with multiple input tensors
- (nullable Tensor *)predictWith:(NSArray<Tensor *> *)inputs;

@end

NS_ASSUME_NONNULL_END
