// hook/build.dart — Native asset build hook for flutter_gpu shader compilation.
//
// ⚠️ DISABLED: flutter_gpu is not yet available on Flutter stable (3.38.x).
// When flutter_gpu lands in stable, uncomment the dependencies in pubspec.yaml
// (flutter_gpu, flutter_gpu_shaders, native_assets_cli) and restore this file:
//
// import 'package:native_assets_cli/native_assets_cli.dart';
// import 'package:flutter_gpu_shaders/build.dart';
//
// void main(List<String> args) async {
//   await build(args, (BuildInput input, BuildOutputBuilder output) async {
//     await buildShaderBundleJson(
//       buildInput: input,
//       buildOutput: output,
//       manifestFileName: 'gpu_shaders.shaderbundle.json',
//     );
//   });
// }

void main(List<String> args) {
  // No-op until flutter_gpu lands in stable.
}
